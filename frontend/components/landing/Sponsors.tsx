export const Sponsors = () => (
  <section className="mx-auto max-w-4xl px-4 py-16 text-center">
    <p className="mb-6 text-xs font-medium uppercase tracking-widest text-stone-500">
      Built with
    </p>
    <div className="flex items-center justify-center gap-12">
      {["ENS", "Uniswap", "Chainlink"].map((name) => (
        <span
          key={name}
          className="text-lg font-medium text-stone-600 opacity-40 transition-opacity hover:opacity-80"
        >
          {name}
        </span>
      ))}
    </div>
  </section>
);
