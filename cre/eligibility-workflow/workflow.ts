import {
	cre,
	EVMClient,
	getNetwork,
	hexToBase64,
	logTriggerConfig,
	ok,
	text,
	type TeeRuntime,
} from '@chainlink/cre-sdk'
import {
	decodeAbiParameters,
	encodeAbiParameters,
	encodeFunctionData,
	decodeFunctionResult,
	keccak256,
	parseAbiParameters,
	stringToHex,
	toBytes,
	toHex,
} from 'viem'
import { z } from 'zod'

// ─── Config Schema ──────────────────────────────────────────
export const configSchema = z.object({
	applicationContractAddress: z.string(),
	mintAttestorAddress: z.string(),
	mainnetRpcUrl: z.string(),
	sepoliaRpcUrl: z.string(),
	resolverAddress: z.string(),
	etherscanBaseUrl: z.string(),
	goplusBaseUrl: z.string(),
	chainalysisOracleAddress: z.string(),
	gasLimit: z.string(),
})
type Config = z.infer<typeof configSchema>

// ─── Constants ──────────────────────────────────────────────

const ROLE_ELIGIBLE_SWAP = 1n << 64n
const ROLE_ELIGIBLE_LIQUIDITY = 1n << 68n

// ApplicationSubmitted(bytes32 indexed applicationId, address indexed wallet,
//   address indexed issuer, address broker, string brokerPath, string label,
//   uint8 requestedTier)
//
// `issuer` and `brokerPath` are derived on-chain by ApplicationContract, not passed in by the
// applicant — brokerPath is the rulebook key, so a caller who could name it would simply pick the
// loosest policy in the book. `label` is what the applicant asked to be called.
const APPLICATION_SUBMITTED_TOPIC = keccak256(
	toHex(
		toBytes('ApplicationSubmitted(bytes32,address,address,address,string,string,uint8)')
	)
)

// Chainalysis oracle ABI — single view function
const SANCTIONS_ABI = [
	{
		name: 'isSanctioned',
		type: 'function' as const,
		inputs: [{ name: 'addr', type: 'address' as const }],
		outputs: [{ name: '', type: 'bool' as const }],
		stateMutability: 'view' as const,
	},
] as const

// ─── Types ──────────────────────────────────────────────────

type PolicyEntry = {
	version: number
	minScore?: number
	minAgeDays?: number
	maxTier?: number
	expiryDays?: number
	jurisdictions?: {
		allow?: string[]
		deny?: string[]
	}
}

type Rulebook = Record<string, PolicyEntry>

type GoPlusResult = {
	sanctioned?: string
	mixer?: string
	phishing_activities?: string
	honeypot_related_address?: string
	malicious_mining_activities?: string
	blacklist_doubt?: string
}

type Verdict = {
	approved: boolean
	roleBitmap: bigint
	expiry: bigint
	reason?: string
}

// ─── Helpers ────────────────────────────────────────────────

function topicToAddress(topic: Uint8Array): `0x${string}` {
	// Topics are 32 bytes, address is last 20 bytes
	const hex = Buffer.from(topic.slice(12)).toString('hex')
	return `0x${hex}` as `0x${string}`
}

function bytesToHexStr(bytes: Uint8Array): `0x${string}` {
	return `0x${Buffer.from(bytes).toString('hex')}` as `0x${string}`
}

// CRE HTTP body is protobuf `bytes`, so JSON representation must be base64.
function toBase64Body(str: string): string {
	return hexToBase64(toHex(toBytes(str)))
}

// ─── Policy Logic (public — in the source code, not the secret) ──

function intersect(a?: string[], b?: string[]): string[] | undefined {
	if (!a) return b
	if (!b) return a
	return a.filter((x) => b.includes(x))
}

function union(a?: string[], b?: string[]): string[] | undefined {
	if (!a) return b
	if (!b) return a
	return [...new Set([...a, ...b])]
}

// Look up the effective policy for a broker path.
// Broker entries override issuer defaults with tighten-only rules.
function lookupPolicy(rulebook: Rulebook, brokerPath: string): PolicyEntry {
	const issuerLabel = brokerPath.split('/')[0]
	const issuerDefault = rulebook[`${issuerLabel}/_default`]

	if (!issuerDefault) {
		throw new Error(`No issuer default policy for "${issuerLabel}"`)
	}

	const brokerOverride = rulebook[brokerPath]
	if (!brokerOverride) return issuerDefault

	return {
		version: brokerOverride.version ?? issuerDefault.version,
		minScore: Math.max(issuerDefault.minScore ?? 0, brokerOverride.minScore ?? 0),
		minAgeDays: Math.max(issuerDefault.minAgeDays ?? 0, brokerOverride.minAgeDays ?? 0),
		maxTier: Math.min(issuerDefault.maxTier ?? 1, brokerOverride.maxTier ?? 1),
		expiryDays: Math.min(issuerDefault.expiryDays ?? 365, brokerOverride.expiryDays ?? 365),
		jurisdictions: {
			allow: intersect(issuerDefault.jurisdictions?.allow, brokerOverride.jurisdictions?.allow),
			deny: union(issuerDefault.jurisdictions?.deny, brokerOverride.jurisdictions?.deny),
		},
	}
}

// Score computation. The formula is public; the thresholds it is compared against are not.
function computeRiskScore(goplus: GoPlusResult, walletAgeDays: number): number {
	let score = 100

	// Hard disqualifiers
	if (goplus.sanctioned === '1') return 0
	if (goplus.mixer === '1') return 0

	// Deductions
	if (goplus.phishing_activities === '1') score -= 40
	if (goplus.honeypot_related_address === '1') score -= 30
	if (goplus.malicious_mining_activities === '1') score -= 20
	if (goplus.blacklist_doubt === '1') score -= 15

	// Wallet age factor
	if (walletAgeDays < 7) score -= 30
	else if (walletAgeDays < 30) score -= 15
	else if (walletAgeDays < 90) score -= 5

	return Math.max(0, score)
}

function evaluate(
	riskScore: number,
	walletAgeDays: number,
	chainalysisSanctioned: boolean,
	goplus: GoPlusResult,
	policy: PolicyEntry,
	requestedTier: number,
	nowSeconds: number,
): Verdict {
	const reject = (reason: string): Verdict => ({
		approved: false,
		roleBitmap: 0n,
		expiry: 0n,
		reason,
	})

	// Layer 1: Chainalysis — HARD REJECT, no policy override
	if (chainalysisSanctioned) return reject('SANCTIONED_CHAINALYSIS')

	// Layer 2: GoPlus sanctions
	if (goplus.sanctioned === '1') return reject('SANCTIONED_GOPLUS')

	// Layer 3: Mixer association
	if (goplus.mixer === '1') return reject('MIXER_ASSOCIATED')

	// Layer 4: Wallet age
	if (walletAgeDays < (policy.minAgeDays ?? 0)) return reject('WALLET_TOO_NEW')

	// Layer 5: Risk score vs policy threshold
	if (riskScore < (policy.minScore ?? 0)) return reject('SCORE_BELOW_THRESHOLD')

	// Layer 6: Tier — broker can cap below what was requested
	const actualTier = Math.min(requestedTier, policy.maxTier ?? 1)

	// Layer 7: Role bitmap from tier
	let roleBitmap = ROLE_ELIGIBLE_SWAP
	if (actualTier >= 1) {
		roleBitmap = ROLE_ELIGIBLE_SWAP | ROLE_ELIGIBLE_LIQUIDITY
	}

	// Layer 8: Expiry
	const expiry = BigInt(nowSeconds + (policy.expiryDays ?? 365) * 86400)

	return { approved: true, roleBitmap, expiry }
}

// ─── Data Source Calls (inside the enclave) ──────────────────

function checkChainalysis(
	runtime: TeeRuntime<Config>,
	wallet: `0x${string}`,
): boolean {
	const config = runtime.config
	const httpClient = new cre.capabilities.HTTPClient()

	const calldata = encodeFunctionData({
		abi: SANCTIONS_ABI,
		functionName: 'isSanctioned',
		args: [wallet],
	})

	const resp = httpClient
		.sendRequest(runtime, {
			url: config.mainnetRpcUrl,
			method: 'POST',
			multiHeaders: { 'Content-Type': { values: ['application/json'] } },
			body: toBase64Body(JSON.stringify({
				jsonrpc: '2.0',
				id: 1,
				method: 'eth_call',
				params: [
					{ to: config.chainalysisOracleAddress, data: calldata },
					'latest',
				],
			})),
		})
		.result()

	if (!ok(resp)) {
		// If the oracle call fails, fail open is NOT acceptable for sanctions.
		// Log and reject.
		// Operational only: names the failing dependency, never the consequence for this applicant.
		runtime.log('Chainalysis: RPC call failed')
		return true // treat as sanctioned (fail closed)
	}

	const rpcResult = JSON.parse(text(resp))
	runtime.log(`Chainalysis raw response: ${JSON.stringify(rpcResult)}`)
	if (rpcResult.error || !rpcResult.result) {
		runtime.log('Chainalysis: RPC returned an error')
		return true
	}

	const sanctioned = decodeFunctionResult({
		abi: SANCTIONS_ABI,
		functionName: 'isSanctioned',
		data: rpcResult.result as `0x${string}`,
	}) as boolean

	runtime.log(`Chainalysis isSanctioned=${sanctioned}`)
	return sanctioned
}

// ─── Pure-JS SHA1 (needed for GoPlus token signing inside the enclave) ───
// The CRE WASM sandbox has no Node.js `crypto`. This is a minimal, standards-
// conformant SHA1 used only for the GoPlus auth flow (sign = sha1(key+time+secret)).
function sha1(message: string): string {
	const encode = (s: string) => {
		const bytes: number[] = []
		for (let i = 0; i < s.length; i++) {
			const c = s.charCodeAt(i)
			if (c < 0x80) bytes.push(c)
			else if (c < 0x800) { bytes.push(0xc0 | (c >> 6)); bytes.push(0x80 | (c & 0x3f)) }
			else { bytes.push(0xe0 | (c >> 12)); bytes.push(0x80 | ((c >> 6) & 0x3f)); bytes.push(0x80 | (c & 0x3f)) }
		}
		return bytes
	}
	const utf8 = encode(message)
	const bitLen = utf8.length * 8

	// Padding
	utf8.push(0x80)
	while (utf8.length % 64 !== 56) utf8.push(0)
	// Append length as 64-bit big-endian (message < 2^32 bits for our use case)
	for (let i = 56; i >= 0; i -= 8) utf8.push(0) // high 32 bits = 0
	utf8.splice(utf8.length - 4) // remove last 4 zeros we just added
	utf8.push((bitLen >>> 24) & 0xff, (bitLen >>> 16) & 0xff, (bitLen >>> 8) & 0xff, bitLen & 0xff)

	let h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0
	const rotl = (v: number, n: number) => ((v << n) | (v >>> (32 - n))) >>> 0

	for (let offset = 0; offset < utf8.length; offset += 64) {
		const w: number[] = new Array(80)
		for (let i = 0; i < 16; i++) {
			w[i] = ((utf8[offset + i * 4] << 24) | (utf8[offset + i * 4 + 1] << 16) |
				(utf8[offset + i * 4 + 2] << 8) | utf8[offset + i * 4 + 3]) >>> 0
		}
		for (let i = 16; i < 80; i++) w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)

		let a = h0, b = h1, c = h2, d = h3, e = h4
		for (let i = 0; i < 80; i++) {
			let f: number, k: number
			if (i < 20) { f = ((b & c) | (~b & d)) >>> 0; k = 0x5a827999 }
			else if (i < 40) { f = (b ^ c ^ d) >>> 0; k = 0x6ed9eba1 }
			else if (i < 60) { f = ((b & c) | (b & d) | (c & d)) >>> 0; k = 0x8f1bbcdc }
			else { f = (b ^ c ^ d) >>> 0; k = 0xca62c1d6 }
			const temp = (rotl(a, 5) + f + e + k + w[i]) >>> 0
			e = d; d = c; c = rotl(b, 30); b = a; a = temp
		}
		h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0
	}

	const hex = (n: number) => n.toString(16).padStart(8, '0')
	return hex(h0) + hex(h1) + hex(h2) + hex(h3) + hex(h4)
}

// ─── GoPlus two-step auth: sign → get access_token → use Bearer ───
function getGoPlusToken(
	runtime: TeeRuntime<Config>,
	appKey: string,
	appSecret: string,
): string {
	const httpClient = new cre.capabilities.HTTPClient()
	const time = Math.floor(Date.now() / 1000)
	const sign = sha1(`${appKey}${time}${appSecret}`)

	const resp = httpClient
		.sendRequest(runtime, {
			url: `${runtime.config.goplusBaseUrl}/token`,
			method: 'POST',
			multiHeaders: { 'Content-Type': { values: ['application/json'] } },
			body: toBase64Body(JSON.stringify({ app_key: appKey, time, sign })),
		})
		.result()

	if (!ok(resp)) {
		runtime.log('GoPlus token request failed')
		return ''
	}

	const body = JSON.parse(text(resp))
	return body.result?.access_token ?? ''
}

function checkGoPlus(
	runtime: TeeRuntime<Config>,
	appKey: string,
	appSecret: string,
	wallet: `0x${string}`,
): GoPlusResult {
	const config = runtime.config
	const httpClient = new cre.capabilities.HTTPClient()

	// Step 1: Get access token using app_key + app_secret
	const accessToken = getGoPlusToken(runtime, appKey, appSecret)
	if (!accessToken) {
		runtime.log('GoPlus: no access token — returning empty risk profile')
		return {}
	}

	// Step 2: Call address_security with Bearer token
	const resp = httpClient
		.sendRequest(runtime, {
			url: `${config.goplusBaseUrl}/address_security/${wallet}?chain_id=1`,
			method: 'GET',
			multiHeaders: {
				Authorization: { values: [accessToken.startsWith('Bearer ') ? accessToken : `Bearer ${accessToken}`] },
			},
		})
		.result()

	if (!ok(resp)) {
		runtime.log('GoPlus API call failed — returning empty risk profile')
		return {}
	}

	const body = JSON.parse(text(resp))
	return (body.result ?? {}) as GoPlusResult
}

function checkWalletAge(
	runtime: TeeRuntime<Config>,
	etherscanKey: string,
	wallet: `0x${string}`,
	nowSeconds: number,
): number {
	const config = runtime.config
	const httpClient = new cre.capabilities.HTTPClient()

	// Fetch the first-ever transaction for this wallet (sort=asc, offset=1)
	const url =
		`${config.etherscanBaseUrl}?chainid=1&module=account&action=txlist` +
		`&address=${wallet}&startblock=0&endblock=99999999` +
		`&page=1&offset=1&sort=asc&apikey=${etherscanKey}`

	const resp = httpClient.sendRequest(runtime, { url, method: 'GET' }).result()

	if (!ok(resp)) {
		runtime.log('Etherscan API call failed — wallet age = 0')
		return 0
	}

	const body = JSON.parse(text(resp))
	const firstTx = body.result?.[0]
	if (!firstTx?.timeStamp) return 0

	const walletAgeDays = Math.floor(
		(nowSeconds - Number(firstTx.timeStamp)) / 86400
	)
	return Math.max(0, walletAgeDays)
}

// ─── Policy Chain — on-chain text record verification ─────────

// PermissionedResolver.text(bytes32 node, string key) → string
const TEXT_RESOLVER_ABI = [
	{
		name: 'text',
		type: 'function' as const,
		inputs: [
			{ name: 'node', type: 'bytes32' as const },
			{ name: 'key', type: 'string' as const },
		],
		outputs: [{ name: '', type: 'string' as const }],
		stateMutability: 'view' as const,
	},
] as const

// Standard ENS namehash for "eth"
const ETH_NAMEHASH =
	'0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae' as `0x${string}`

// Compute namehash for a broker from its brokerPath.
// brokerPath = "acme/prime" → namehash("prime.acme.canopy.eth")
function computeBrokerNode(brokerPath: string): `0x${string}` {
	// Start from canopy.eth
	const canopyLabel = keccak256(toHex(toBytes('canopy')))
	let node = keccak256(
		`0x${ETH_NAMEHASH.slice(2)}${canopyLabel.slice(2)}` as `0x${string}`
	)

	// Walk the path: "acme/prime" → hash "acme", then "prime"
	const segments = brokerPath.split('/')
	for (const segment of segments) {
		const labelHash = keccak256(toHex(toBytes(segment)))
		node = keccak256(
			`0x${node.slice(2)}${labelHash.slice(2)}` as `0x${string}`
		)
	}

	return node
}

// Read a text record from the PermissionedResolver on Sepolia via HTTP eth_call.
// Returns null on failure or when no record exists — the caller decides what that means.
function readTextRecord(
	runtime: TeeRuntime<Config>,
	resolverAddress: string,
	node: `0x${string}`,
	key: string,
): string | null {
	const config = runtime.config
	const httpClient = new cre.capabilities.HTTPClient()

	const calldata = encodeFunctionData({
		abi: TEXT_RESOLVER_ABI,
		functionName: 'text',
		args: [node, key],
	})

	const resp = httpClient
		.sendRequest(runtime, {
			url: config.sepoliaRpcUrl,
			method: 'POST',
			multiHeaders: { 'Content-Type': { values: ['application/json'] } },
			body: toBase64Body(
				JSON.stringify({
					jsonrpc: '2.0',
					id: 1,
					method: 'eth_call',
					params: [
						{ to: resolverAddress, data: calldata },
						'latest',
					],
				})
			),
		})
		.result()

	if (!ok(resp)) {
		runtime.log('Text record read failed — skipping policy verification')
		return null
	}

	const rpcResult = JSON.parse(text(resp))
	if (rpcResult.error || !rpcResult.result || rpcResult.result === '0x') {
		return null
	}

	const decoded = decodeFunctionResult({
		abi: TEXT_RESOLVER_ABI,
		functionName: 'text',
		data: rpcResult.result as `0x${string}`,
	}) as string

	return decoded || null
}

// ─── Main TEE Handler ───────────────────────────────────────
// Everything in this function runs inside the AWS Nitro enclave until
// we explicitly cross back with `usingTheDons()`.
//
// What is confidential:
//   - Vault-DON secrets (API keys, ELIGIBILITY_RULEBOOK thresholds)
//   - HTTP request/response payloads (Chainalysis, GoPlus, Etherscan raw data)
//   - Intermediate values (risk score, effective policy, evaluation result)
//
// What is NOT confidential:
//   - This source code (the repo is public)
//   - The trigger event data (runs on DON nodes, not in the enclave)
//   - The report tuple (on-chain calldata after writeReport)

export const onApplicationSubmitted = (
	runtime: TeeRuntime<Config>,
	log: { topics: Uint8Array[]; data: Uint8Array },
): string => {
	const config = runtime.config
	const nowSeconds = Math.floor(Date.now() / 1000)

	// ── Step 1: Decode the trigger event ──
	// Indexed params: topics[0]=eventSig, topics[1]=applicationId,
	//                 topics[2]=wallet, topics[3]=issuer
	// Non-indexed: (address broker, string brokerPath, string label, uint8 requestedTier)
	const wallet = topicToAddress(log.topics[2])

	// The issuer is not read here on purpose. ApplicationContract derives both the issuer and the
	// brokerPath from the broker's registry, so they cannot disagree — and MintAttestor derives the
	// issuer again on-chain to pick the checker. Nothing this handler decides depends on it.
	const _issuer = topicToAddress(log.topics[3])

	const [broker, brokerPath, label, requestedTier] = decodeAbiParameters(
		parseAbiParameters('address broker, string brokerPath, string label, uint8 requestedTier'),
		bytesToHexStr(log.data),
	)

	runtime.log(
		`Processing application: wallet=${wallet}, brokerPath=${brokerPath}, label=${label}`
	)

	// ── Step 2: Fetch all secrets inside the enclave ──
	// The Vault DON releases these only into an attested enclave.
	const secrets = runtime
		.getSecrets([
			{ id: 'GOPLUS_APP_KEY' },
			{ id: 'GOPLUS_APP_SECRET' },
			{ id: 'ELIGIBILITY_RULEBOOK' },
			{ id: 'ETHERSCAN_API_KEY' },
		])
		.result()

	const goplusAppKey = secrets['GOPLUS_APP_KEY'].value
	const goplusAppSecret = secrets['GOPLUS_APP_SECRET'].value
	const rulebook: Rulebook = JSON.parse(secrets['ELIGIBILITY_RULEBOOK'].value)
	const etherscanKey = secrets['ETHERSCAN_API_KEY'].value

	// ── Step 3: Chainalysis sanctions check ──
	// Real OFAC data from mainnet oracle via HTTP eth_call.
	// The wallet address is the same across all chains.
	const isSanctioned = checkChainalysis(runtime, wallet)

	// ── Step 4: GoPlus risk assessment ──
	// Real risk data: sanctions, mixer, phishing, honeypot, malicious activity.
	// The raw response stays inside the enclave.
	const goplusResult = checkGoPlus(runtime, goplusAppKey, goplusAppSecret, wallet)

	// ── Step 5: Etherscan wallet history ──
	// Real on-chain history: wallet age from first transaction.
	const walletAgeDays = checkWalletAge(runtime, etherscanKey, wallet, nowSeconds)

	// ── Step 6: Look up and combine policy ──
	// The RULEBOOK is a Vault-DON secret. Broker overrides tighten, never loosen.
	const effectivePolicy = lookupPolicy(rulebook, brokerPath)

	// ── Step 6b: Verify policy hash against on-chain text record ──
	// The broker's policy hash is pinned to their ENS name as a text record.
	// Verifying it proves the CRE evaluated against the policy the broker committed to,
	// not a secretly rewritten one.
	let policyMismatch = false
	const brokerNode = computeBrokerNode(brokerPath)
	const onChainPolicyText = readTextRecord(
		runtime,
		config.resolverAddress,
		brokerNode,
		'canopy:policy'
	)

	if (onChainPolicyText) {
		// Extract the hash from "keccak256:0x..."
		const onChainHash = onChainPolicyText.replace('keccak256:', '')

		// Compute hash of the effective policy body from the rulebook.
		// Use the broker-specific entry if it exists, otherwise the issuer default.
		const issuerLabel = brokerPath.split('/')[0]
		const policyBody =
			rulebook[brokerPath] ?? rulebook[`${issuerLabel}/_default`]
		const canonical = JSON.stringify(
			policyBody,
			Object.keys(policyBody).sort()
		)
		const computedHash = keccak256(toHex(toBytes(canonical)))

		if (onChainHash.toLowerCase() !== computedHash.toLowerCase()) {
			runtime.log(
				'Policy hash mismatch — on-chain anchor differs from Vault-DON body'
			)
			policyMismatch = true
		}
	}
	// If no text record is set, skip verification (backwards-compatible with pre-policy names).
	// If the RPC read failed, skip verification (fail-open on read, fail-closed on mismatch).

	// ── Step 7: Compute risk score ──
	// The formula is public (in this source code). The thresholds it is compared
	// against (minScore, minAgeDays, etc.) are in the secret RULEBOOK.
	const riskScore = computeRiskScore(goplusResult, walletAgeDays)

	runtime.log(`GoPlus flags: ${JSON.stringify(goplusResult)}`)
	runtime.log(`WalletAgeDays=${walletAgeDays}, RiskScore=${riskScore}`)

	// ── Step 8: Evaluate against policy ──
	const verdict = policyMismatch
		? {
				approved: false,
				roleBitmap: 0n,
				expiry: 0n,
				reason: 'POLICY_MISMATCH',
			}
		: evaluate(
				riskScore,
				walletAgeDays,
				isSanctioned,
				goplusResult,
				effectivePolicy,
				requestedTier,
				nowSeconds,
			)

	// Deliberately not logged. `verdict.reason` names the factor that decided the case
	// (SCORE_BELOW_THRESHOLD, MIXER_ASSOCIATED, WALLET_TOO_NEW), and "which specific factors caused
	// a rejection" is on the confidential side of our own boundary — logging it here would be the
	// one place our code contradicts the claim the whole design rests on. CRE's guidance is the
	// same: avoid logging inside enclave execution logic.
	//
	// The binary verdict is public regardless: it rides out in the report's `approved` field.

	// ── Step 9: The label ──
	// Comes from the application, not derived here. ApplicationContract has already checked that it
	// is 1–32 bytes and not already live under this broker, so it fits the report's bytes32 and can
	// actually be minted. Deriving it from the wallet would produce names like
	// `d8da6bf26964af9d.prime.acme.canopy.eth` instead of `alice.prime.acme.canopy.eth`.
	const labelBytes = stringToHex(label, { size: 32 })

	// ── Step 10: Encode the report tuple ──
	// Matches MintAttestor's abi.decode exactly:
	//   (uint8 kind, address subject, bytes32 labelBytes, address parentRegistry,
	//    uint256 roleBitmap, uint64 expiry, bool approved)
	const reportData = encodeAbiParameters(
		parseAbiParameters(
			'uint8 kind, address subject, bytes32 labelBytes, address parentRegistry, uint256 roleBitmap, uint64 expiry, bool approved'
		),
		[
			0,                     // kind = investor
			wallet,                // subject
			labelBytes,            // label as bytes32
			broker as `0x${string}`, // parentRegistry (broker's registry)
			verdict.roleBitmap,    // role bits
			verdict.expiry,        // absolute Unix timestamp
			verdict.approved,      // true/false
		],
	)

	// ════════════ CROSSING THE CONFIDENTIALITY BOUNDARY ════════════
	// Everything after usingTheDons() executes on Workflow DON nodes.
	// Only the verdict tuple crosses — no raw API responses, no scores,
	// no thresholds, no PII.
	const donRuntime = runtime.usingTheDons()

	const report = donRuntime
		.report({
			encodedPayload: hexToBase64(reportData),
			encoderName: 'evm',
			signingAlgo: 'ecdsa',
			hashingAlgo: 'keccak256',
		})
		.result()

	// ── Step 11: Deliver the DON-signed report to MintAttestor on Sepolia ──
	const sepoliaNetwork = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: 'ethereum-testnet-sepolia',
		isTestnet: true,
	})
	if (!sepoliaNetwork) throw new Error('Sepolia network not found')
	const sepoliaClient = new EVMClient(sepoliaNetwork.chainSelector.selector)

	sepoliaClient
		.writeReport(donRuntime, {
			receiver: config.mintAttestorAddress as `0x${string}`,
			report,
			gasConfig: { gasLimit: config.gasLimit },
		})
		.result()

	// Same reasoning as above: the return value surfaces in simulation output, so it carries the
	// verdict and not the reason for it.
	return verdict.approved ? 'APPROVED' : 'REJECTED'
}

// ─── Workflow Init ──────────────────────────────────────────
export function initWorkflow(config: Config) {
	const sepoliaNetwork = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: 'ethereum-testnet-sepolia',
		isTestnet: true,
	})
	if (!sepoliaNetwork) throw new Error('Sepolia network not found')
	const sepoliaClient = new EVMClient(sepoliaNetwork.chainSelector.selector)

	const trigger = sepoliaClient.logTrigger(
		logTriggerConfig({
			addresses: [config.applicationContractAddress as `0x${string}`],
			topics: [[APPLICATION_SUBMITTED_TOPIC]],
			// LATEST, not FINALIZED. Finality on Sepolia is two epochs — about 13 minutes — which
			// is the gap between an applicant pressing Submit and their subname appearing. That is
			// fine for a compliance system and fatal for a live demo, where beat 1 has to land
			// while someone is watching. A reorg would at worst mint a subname for an application
			// that no longer exists on-chain, and the name still expires on its own.
			confidence: 'LATEST',
		})
	)

	return [
		cre.handlerInTee(
			trigger,
			onApplicationSubmitted,
			[{ tee: 'nitro', regions: ['us-west-2'] }],
		),
	]
}
