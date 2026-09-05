// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {RegistryRolesLib} from "@ens/registry/libraries/RegistryRolesLib.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {ENSAllowlistChecker} from "../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../src/checker/CanopyRoles.sol";

/// @dev One `(account, roleBitmap)` pair for the deployed `UserRegistry` initializer.
struct RoleGrant {
    address account;
    uint256 roleBitmap;
}

/// @dev An investor subname: the label, the wallet that owns it, and the eligibility it carries.
struct Investor {
    string label;
    address wallet;
    uint256 roles;
}

/// @dev Minimal local interfaces. Declared here rather than imported so this script does not pull
///      in `ETHRegistrar.sol`, whose `LabelStore` dependency reaches into the `ens-contracts`
///      submodule we deliberately do not clone.
interface IETHRegistrarLike {
    function makeCommitment(
        string calldata label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        bytes32 referrer
    ) external pure returns (bytes32);

    function commit(bytes32 commitment) external;

    function register(
        string calldata label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        address paymentToken,
        bytes32 referrer
    ) external returns (uint256 tokenId);

    function commitmentAt(bytes32 commitment) external view returns (uint64);
    function isAvailable(string calldata label) external view returns (bool);
    function getRegisterPrice(string calldata label, uint64 duration, address paymentToken)
        external
        view
        returns (uint256 base, uint256 premium);
    function MIN_COMMITMENT_AGE() external view returns (uint64);
    function MIN_REGISTER_DURATION() external view returns (uint64);
}

interface IVerifiableFactoryLike {
    function deployProxy(address implementation, uint256 salt, bytes calldata data)
        external
        returns (address);
}

/// @dev The deployed implementation takes an ARRAY of grants — not `(address, uint256)`.
///      Selector `0x37cb53a8`. See the spec's "Selectors that differ from our pinned source".
interface IUserRegistryLike {
    function initialize(RoleGrant[] calldata grants) external;
}

interface IMockUSDCLike {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Build the Canopy issuer hierarchy on Sepolia
///
/// @notice Run in phases, because registration is commit–reveal and the 60-second wait cannot
///         happen inside a single broadcast:
///
///         forge script script/DeployIssuerHierarchy.s.sol --sig "commitParent()"  --rpc-url sepolia --broadcast
///         (wait 60s)
///         forge script script/DeployIssuerHierarchy.s.sol --sig "registerParent()" --rpc-url sepolia --broadcast
///         forge script script/DeployIssuerHierarchy.s.sol --sig "buildHierarchy()" --rpc-url sepolia --broadcast
///         forge script script/DeployIssuerHierarchy.s.sol --sig "deployChecker()"  --rpc-url sepolia --broadcast
///         forge script script/DeployIssuerHierarchy.s.sol --sig "verify()"         --rpc-url sepolia
///
/// @dev Every phase is idempotent: it checks on-chain state first and skips work already done, so a
///      re-run after a failed transaction resumes rather than duplicating. Addresses are persisted
///      to `deployments.json` at the repo root, which is also the address book Builder B reads.
contract DeployIssuerHierarchy is Script {
    // ---------------------------------------------------------------------
    // Live hackathon deployment — verified Sep 5
    // ---------------------------------------------------------------------

    address internal constant ETH_REGISTRY = 0x1D78834d97c1D7b1A38c1deDBD1a287cFEd3971e;
    address internal constant ETH_REGISTRAR = 0x7d1B7f586a62Ac3F54b9A396849757814283270b;
    address internal constant VERIFIABLE_FACTORY = 0x894bc9cC8ff1ad96B8a288C86A8C71D662C07780;
    address internal constant USER_REGISTRY_IMPL = 0x47B442d0CF617c41CAbAFf5f02f44DD1e5f72546;
    address internal constant MOCK_USDC = 0xcBFD80F74375c54E545AF34788Ff465F96F66F05;

    // ---------------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------------

    /// @dev The parent is registered through the registrar, which enforces
    ///      `MIN_REGISTER_DURATION` (28 days). Subnames below have no minimum.
    uint64 internal constant PARENT_DURATION = 365 days;

    /// @dev Overridable so a burnt or contested name can be abandoned without editing code.
    ///      The parent costs a 60s commit--reveal, so changing it is the one expensive change.
    function _parentLabel() internal view returns (string memory) {
        return vm.envOr("PARENT_LABEL", string("canopy"));
    }

    // ---------------------------------------------------------------------
    // script/hierarchy.json
    //
    // Parsed field by field with explicit index paths rather than decoded into a struct array.
    // Foundry's JSON-to-struct decoding orders fields alphabetically by key, which silently
    // mismatches any struct whose declaration order differs — a corruption, not an error.
    // ---------------------------------------------------------------------

    function _config() internal view returns (string memory) {
        return vm.readFile(vm.envOr("HIERARCHY_CONFIG", string("./script/hierarchy.json")));
    }

    /// @dev Counted by probing index paths. `vm.parseJsonStringArray` with a `[*]` projection is
    ///      rejected — it requires a path resolving to exactly one JSON node.
    function _count(string memory json, string memory prefix, string memory suffix)
        internal
        view
        returns (uint256 n)
    {
        while (vm.keyExistsJson(json, string.concat(prefix, vm.toString(n), suffix))) {
            n++;
        }
    }

    function _brokerLabels() internal view returns (string[] memory labels) {
        string memory json = _config();
        uint256 n = _count(json, ".brokers[", "].label");

        labels = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            labels[i] = vm.parseJsonString(json, string.concat(".brokers[", vm.toString(i), "].label"));
        }
    }

    /// @dev Per-broker expiry. `0` (or absent) falls back to `BROKER_TTL`, which the demo shortens
    ///      to film the lapse. A broker that must survive that lapse needs an explicit long value,
    ///      or a global short TTL expires every broker at once and the cascade stops looking scoped.
    function _brokerExpiryOf(uint256 b) internal view returns (uint64) {
        string memory json = _config();
        string memory path = string.concat(".brokers[", vm.toString(b), "].ttl");

        if (vm.keyExistsJson(json, path)) {
            uint256 ttl = vm.parseJsonUint(json, path);
            if (ttl > 0) return uint64(block.timestamp + ttl);
        }
        return _brokerExpiry();
    }

    /// @dev The bootstrap investors under broker `b`.
    function _investorsOf(uint256 b) internal view returns (Investor[] memory list) {
        string memory json = _config();
        string memory base = string.concat(".brokers[", vm.toString(b), "]");

        uint256 n = _count(json, string.concat(base, ".investors["), "].label");
        list = new Investor[](n);

        for (uint256 i = 0; i < n; i++) {
            string memory at = string.concat(base, ".investors[", vm.toString(i), "]");
            string memory label = vm.parseJsonString(json, string.concat(at, ".label"));

            uint256 roles;
            if (vm.parseJsonBool(json, string.concat(at, ".swap"))) roles |= CanopyRoles.ROLE_ELIGIBLE_SWAP;
            if (vm.parseJsonBool(json, string.concat(at, ".liquidity"))) {
                roles |= CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY;
            }

            list[i] = Investor({label: label, wallet: _walletFor(json, at, label), roles: roles});
        }
    }

    /// @dev An empty `wallet` yields a deterministic placeholder. Placeholders cannot sign, so any
    ///      investor who transacts on camera needs a real address in the config.
    function _walletFor(string memory json, string memory at, string memory label)
        internal
        view
        returns (address)
    {
        string memory raw = vm.parseJsonString(json, string.concat(at, ".wallet"));
        if (bytes(raw).length > 0) return vm.parseAddress(raw);

        address placeholder =
            address(uint160(uint256(keccak256(abi.encodePacked("canopy.investor", label, _deployer())))));
        console2.log("WARNING: no wallet configured, using placeholder (cannot sign)", label, placeholder);
        return placeholder;
    }

    /// @notice The two investors the tier split needs.
    /// @dev Every bootstrap investor across every broker, flattened.
    function _allInvestors() internal view returns (Investor[] memory list) {
        string[] memory brokers = _brokerLabels();

        uint256 n;
        for (uint256 b = 0; b < brokers.length; b++) {
            n += _investorsOf(b).length;
        }

        list = new Investor[](n);
        uint256 k;
        for (uint256 b = 0; b < brokers.length; b++) {
            Investor[] memory some = _investorsOf(b);
            for (uint256 i = 0; i < some.length; i++) {
                list[k++] = some[i];
            }
        }
    }

    /// @dev Roles the deployer holds on each registry we own. Each role is paired with its `_ADMIN`
    ///      twin so the deployer can also delegate it later — notably granting `ROLE_REGISTRAR` to
    ///      `SubnameRegistrar` on Day 4, whose address is not known yet.
    uint256 internal constant OPERATOR_ROLES = RegistryRolesLib.ROLE_REGISTRAR
        | RegistryRolesLib.ROLE_REGISTRAR_ADMIN | RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_RENEW_ADMIN
        | RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN
        | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_PARENT_ADMIN
        | RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN
        | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN;

    /// @dev Overridable so a fork rehearsal can write to a scratch file instead of the real
    ///      address book Builder B reads.
    function _deployments() internal view returns (string memory) {
        return vm.envOr("DEPLOYMENTS_PATH", string("../deployments.json"));
    }

    // ---------------------------------------------------------------------

    /// @notice Deploy the issuer registry, then commit to the parent name.
    /// @dev The registry must exist first: `makeCommitment` binds the subregistry, so committing
    ///      before it is deployed would commit to the wrong hierarchy.
    function commitParent() public {
        address deployer = _deployer();
        vm.startBroadcast(_key());

        address issuerRegistry = _ensureIssuerRegistry(deployer);

        // A consumed commitment is deleted on-chain, so `commitmentAt` reads zero again after a
        // successful registration. Without this check a re-run would send a pointless commit and
        // make the driver wait out MIN_COMMITMENT_AGE for nothing.
        if (!IETHRegistrarLike(ETH_REGISTRAR).isAvailable(_parentLabel())) {
            console2.log("parent already registered, nothing to commit");
            vm.stopBroadcast();
            return;
        }

        _ensureFunded(deployer);

        bytes32 commitment = IETHRegistrarLike(ETH_REGISTRAR).makeCommitment(
            _parentLabel(), deployer, _secret(deployer), IRegistry(issuerRegistry), address(0), PARENT_DURATION, bytes32(0)
        );

        if (IETHRegistrarLike(ETH_REGISTRAR).commitmentAt(commitment) != 0) {
            console2.log("commitment already made, skipping");
        } else {
            IETHRegistrarLike(ETH_REGISTRAR).commit(commitment);
            console2.log("committed. wait MIN_COMMITMENT_AGE seconds, then run registerParent()");
            console2.log("MIN_COMMITMENT_AGE", IETHRegistrarLike(ETH_REGISTRAR).MIN_COMMITMENT_AGE());
        }

        vm.stopBroadcast();
    }

    /// @notice Register the parent name. Requires `commitParent()` at least 60s earlier.
    function registerParent() public {
        address deployer = _deployer();
        address issuerRegistry = _load("issuerRegistry");
        require(issuerRegistry != address(0), "run commitParent() first");

        vm.startBroadcast(_key());

        if (!IETHRegistrarLike(ETH_REGISTRAR).isAvailable(_parentLabel())) {
            console2.log("parent already registered, skipping");
        } else {
            (uint256 base, uint256 premium) =
                IETHRegistrarLike(ETH_REGISTRAR).getRegisterPrice(_parentLabel(), PARENT_DURATION, MOCK_USDC);
            uint256 price = base + premium;

            _ensureFunded(deployer);
            IMockUSDCLike(MOCK_USDC).approve(ETH_REGISTRAR, price);

            IETHRegistrarLike(ETH_REGISTRAR).register(
                _parentLabel(),
                deployer,
                _secret(deployer),
                IRegistry(issuerRegistry),
                address(0),
                PARENT_DURATION,
                MOCK_USDC,
                bytes32(0)
            );
            console2.log("registered parent, price paid", price);
        }

        // The reverse pointer. `register` above set .eth -> issuerRegistry; this sets the other
        // direction, which is what the checker's upward walk needs. See _ancestorsAlive().
        _ensureParent(issuerRegistry, ETH_REGISTRY, _parentLabel());

        vm.stopBroadcast();
    }

    /// @notice Deploy a registry for every broker in `script/hierarchy.json` and register the
    ///         broker names, plus the bootstrap investors listed under each.
    ///
    /// @dev Converges the chain to the config: add a broker to the JSON, re-run, and only the
    ///      missing pieces are created. Brokers are issuer infrastructure — no CRE involved.
    ///
    ///      The investors here are **bootstrap only**. In the real flow they arrive via
    ///      application -> CRE verdict -> `MintAttestor` -> `SubnameRegistrar`. Keep this list to
    ///      the few needed before CRE exists on Day 4; adding everyone here bypasses the product.
    function buildHierarchy() public {
        address deployer = _deployer();
        address issuerRegistry = _load("issuerRegistry");
        require(issuerRegistry != address(0), "run commitParent() first");

        string[] memory brokers = _brokerLabels();
        require(brokers.length > 0, "no brokers in script/hierarchy.json");

        vm.startBroadcast(_key());

        for (uint256 b = 0; b < brokers.length; b++) {
            string memory broker = brokers[b];

            address brokerRegistry = _ensureBrokerRegistry(broker);
            _ensureSubname(issuerRegistry, broker, deployer, brokerRegistry, 0, _brokerExpiryOf(b));
            _ensureParent(brokerRegistry, issuerRegistry, broker);

            Investor[] memory investors = _investorsOf(b);
            for (uint256 i = 0; i < investors.length; i++) {
                _ensureSubname(
                    brokerRegistry,
                    investors[i].label,
                    investors[i].wallet,
                    address(0),
                    investors[i].roles,
                    _leafExpiry()
                );
            }
        }

        vm.stopBroadcast();
    }

    /// @notice Deploy the checker and record the investor's leaf.
    /// @dev `recordPath` is `onlyAttestor` and `MintAttestor` does not exist until Day 4, so the
    ///      attestor is the deployer for now and is re-pointed with `setAttestor` tomorrow.
    function deployChecker() public {
        address deployer = _deployer();
        string[] memory brokers = _brokerLabels();

        vm.startBroadcast(_key());

        address token = _permissionedToken();
        ENSAllowlistChecker checker = new ENSAllowlistChecker(IRegistry(ETH_REGISTRY), token, deployer);
        checker.setAttestor(deployer);

        for (uint256 b = 0; b < brokers.length; b++) {
            address brokerRegistry = _load(_registryKey(brokers[b]));
            require(brokerRegistry != address(0), "run buildHierarchy() first");

            Investor[] memory investors = _investorsOf(b);
            for (uint256 i = 0; i < investors.length; i++) {
                checker.recordPath(
                    investors[i].wallet, IPermissionedRegistry(brokerRegistry), LibLabel.id(investors[i].label)
                );
            }
        }

        _save("checker", address(checker));
        _save("permissionedToken", token);
        console2.log("checker", address(checker));

        vm.stopBroadcast();
    }

    /// @notice Re-arm the broker name so the lapse can be rehearsed again immediately.
    ///
    /// @dev Between takes only — NEVER on camera. This unregisters and re-registers `brokerA`,
    ///      and `unregister` is exactly the revocation transaction the whole pitch claims is
    ///      unnecessary. Filming it would refute the thesis.
    ///
    ///      Without this you would have to wait out `BROKER_TTL` to try the lapse a second time.
    ///      Run it with a short `BROKER_TTL` to set up a take, then let the clock run out on its
    ///      own — the lapse itself must still be time passing, not a button.
    ///
    ///      Re-registering does not disturb anything below: the investors live in a different
    ///      registry, and we grant no roles on the broker's own resource, so nothing is orphaned by
    ///      the version bump.
    ///
    /// @param label Which broker to re-arm. Defaults to the first in the config when empty.
    function resetBroker(string memory label) public {
        address issuerRegistry = _load("issuerRegistry");
        if (bytes(label).length == 0) label = _brokerLabels()[0];

        address brokerRegistry = _load(_registryKey(label));
        require(issuerRegistry != address(0) && brokerRegistry != address(0), "run the full deploy first");

        vm.startBroadcast(_key());

        IPermissionedRegistry.State memory state =
            IPermissionedRegistry(issuerRegistry).getState(LibLabel.id(label));

        if (state.status == IPermissionedRegistry.Status.REGISTERED) {
            IPermissionedRegistry(issuerRegistry).unregister(LibLabel.id(label));
            console2.log("unregistered (setup only, not a demo step)", label);
        }

        uint64 expiry = _brokerExpiry();
        IPermissionedRegistry(issuerRegistry).register(
            label, _deployer(), IRegistry(brokerRegistry), address(0), 0, expiry
        );
        console2.log("re-registered broker, expires at", expiry);
        console2.log("seconds until lapse", expiry - block.timestamp);

        vm.stopBroadcast();
    }

    /// @notice The end-of-day criterion: the checker walking the live hierarchy.
    function verify() public view {
        ENSAllowlistChecker checker = ENSAllowlistChecker(_load("checker"));
        address token = _load("permissionedToken");

        Investor[] memory investors = _allInvestors();
        bool sawLiquidityTier;

        for (uint256 i = 0; i < investors.length; i++) {
            PermissionFlag actual = checker.checkAllowlist(investors[i].wallet, token);

            PermissionFlag expected = PermissionFlags.NONE;
            if (investors[i].roles & CanopyRoles.ROLE_ELIGIBLE_SWAP != 0) {
                expected = expected | PermissionFlags.SWAP_ALLOWED;
            }
            if (investors[i].roles & CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY != 0) {
                expected = expected | PermissionFlags.LIQUIDITY_ALLOWED;
                sawLiquidityTier = true;
            }

            console2.log(investors[i].label, uint16(PermissionFlag.unwrap(actual)));
            require(actual == expected, "investor flag does not match configured roles");

            // Evaluated the way PermissionsAdapter.isAllowed evaluates it: containment, not
            // equality. A swap-only investor must fail the liquidity gate — beat 7 rests on this.
            if (investors[i].roles & CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY == 0) {
                require(
                    !((actual & PermissionFlags.LIQUIDITY_ALLOWED) == PermissionFlags.LIQUIDITY_ALLOWED),
                    "swap-only investor must NOT satisfy the liquidity gate"
                );
            }
        }

        PermissionFlag stranger = checker.checkAllowlist(address(0xdead), token);
        console2.log("stranger", uint16(PermissionFlag.unwrap(stranger)));
        require(stranger == PermissionFlags.NONE, "stranger should be NONE");

        // Without a market maker there is no tier split to demonstrate.
        require(sawLiquidityTier, "no investor holds the liquidity tier");
        require(investors.length >= 2, "need at least two investors for the tier split");

        console2.log("OK: tier split holds on live state");
    }

    // ---------------------------------------------------------------------
    // Steps, each idempotent
    // ---------------------------------------------------------------------

    function _ensureIssuerRegistry(address deployer) internal returns (address registry) {
        registry = _load("issuerRegistry");
        if (registry != address(0) && registry.code.length > 0) return registry;

        registry = _deployRegistry(deployer, uint256(keccak256("canopy.issuer.v1")));
        _save("issuerRegistry", registry);
        console2.log("issuerRegistry", registry);
    }

    /// @dev One registry per broker, keyed and salted by label so adding a broker never disturbs
    ///      an existing one.
    function _registryKey(string memory brokerLabel) internal pure returns (string memory) {
        return string.concat("registry_", brokerLabel);
    }

    function _ensureBrokerRegistry(string memory brokerLabel) internal returns (address registry) {
        registry = _load(_registryKey(brokerLabel));
        if (registry != address(0) && registry.code.length > 0) return registry;

        registry = _deployRegistry(
            _deployer(), uint256(keccak256(abi.encodePacked("canopy.broker.v1.", brokerLabel)))
        );
        _save(_registryKey(brokerLabel), registry);
        console2.log("registry for broker", brokerLabel, registry);
    }

    /// @dev A `UserRegistry` proxy. The initializer takes an array of grants; we grant the deployer
    ///      the operator roles plus their `_ADMIN` twins so `SubnameRegistrar` can be added later
    ///      with `grantRootRoles`.
    function _deployRegistry(address deployer, uint256 salt) internal returns (address) {
        RoleGrant[] memory grants = new RoleGrant[](1);
        grants[0] = RoleGrant({account: deployer, roleBitmap: OPERATOR_ROLES});

        return IVerifiableFactoryLike(VERIFIABLE_FACTORY).deployProxy(
            USER_REGISTRY_IMPL, salt, abi.encodeCall(IUserRegistryLike.initialize, (grants))
        );
    }

    /// @dev `setSubregistry` on the parent does NOT wire this direction. Without it the checker's
    ///      upward walk finds no parent, stops early, and denies everything.
    function _ensureParent(address child, address parent, string memory label) internal {
        (IRegistry current,) = IRegistry(child).getParent();
        if (address(current) == parent) return;
        IPermissionedRegistry(child).setParent(IRegistry(parent), label);
        console2.log("setParent wired for", child);
    }

    function _ensureSubname(
        address registry,
        string memory label,
        address owner,
        address subregistry,
        uint256 roleBitmap,
        uint64 expiry
    ) internal {
        IPermissionedRegistry.State memory state = IPermissionedRegistry(registry).getState(LibLabel.id(label));
        if (state.status == IPermissionedRegistry.Status.REGISTERED && state.expiry > block.timestamp) {
            console2.log("subname already live, skipping", label);
            return;
        }
        IPermissionedRegistry(registry).register(
            label, owner, IRegistry(subregistry), address(0), roleBitmap, expiry
        );
        console2.log("registered", label);
    }

    function _ensureFunded(address deployer) internal {
        if (IMockUSDCLike(MOCK_USDC).balanceOf(deployer) >= 100e6) return;
        IMockUSDCLike(MOCK_USDC).mint(deployer, 1_000e6); // mint is permissionless
    }

    // ---------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------

    function _key() internal view returns (uint256) {
        return vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    /// @dev Broadcasting with the key rather than the address keeps the script self-contained —
    ///      no `--private-key` flag, and forge does not need the signer pre-registered.
    function _deployer() internal view returns (address) {
        return vm.addr(_key());
    }


    /// @dev Must be identical across `commitParent()` and `registerParent()`, and unguessable to
    ///      anyone who could front-run the registration.
    function _secret(address deployer) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("canopy.commit.v1", deployer, vm.envOr("COMMIT_NONCE", uint256(1))));
    }

    /// @dev Long by default. The ~10-minute value is for filming only — set it on a build day and
    ///      the broker is dead for every test that follows.
    function _brokerExpiry() internal view returns (uint64) {
        return uint64(block.timestamp + vm.envOr("BROKER_TTL", uint256(30 days)));
    }

    function _leafExpiry() internal view returns (uint64) {
        return uint64(block.timestamp + vm.envOr("LEAF_TTL", uint256(60 days)));
    }

    /// @dev `PERMISSIONED_TOKEN` is immutable on the checker, so this must be Builder B's real
    ///      permissioned test token before Day 4. Until it exists, a placeholder still exercises
    ///      the whole walk provided `verify()` passes the same address.
    function _permissionedToken() internal view returns (address) {
        address token = vm.envOr("PERMISSIONED_TOKEN", address(0));
        if (token == address(0)) {
            token = address(uint160(uint256(keccak256("canopy.placeholder.token"))));
            console2.log("WARNING: no PERMISSIONED_TOKEN set, using placeholder", token);
            console2.log("         redeploy the checker once Builder B's token exists");
        }
        return token;
    }

    // ---------------------------------------------------------------------
    // deployments.json
    // ---------------------------------------------------------------------

    function _save(string memory key, address value) internal {
        string memory json = _readDeployments();
        // Rebuild the object so existing keys survive.
        string[] memory keys = vm.parseJsonKeys(json, "$");
        string memory out;
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) continue;
            out = vm.serializeAddress("deployments", keys[i], vm.parseJsonAddress(json, string.concat(".", keys[i])));
        }
        out = vm.serializeAddress("deployments", key, value);
        vm.writeJson(out, _deployments());
    }

    function _load(string memory key) internal view returns (address) {
        string memory json = _readDeployments();
        if (!vm.keyExistsJson(json, string.concat(".", key))) return address(0);
        return vm.parseJsonAddress(json, string.concat(".", key));
    }

    function _readDeployments() internal view returns (string memory json) {
        try vm.readFile(_deployments()) returns (string memory contents) {
            json = bytes(contents).length == 0 ? "{}" : contents;
        } catch {
            json = "{}";
        }
    }
}
