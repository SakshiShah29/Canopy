"use client";

import PixelBlast from "@/components/PixelBlast";

export function DashboardBackground() {
  return (
    <div className="fixed inset-0 z-0" style={{ width: "100%", height: "100vh" }}>
      <PixelBlast
        variant="square"
        pixelSize={4}
        color="#FFFBB8"
        patternScale={2}
        patternDensity={1}
        pixelSizeJitter={0}
        enableRipples
        rippleSpeed={0.4}
        rippleThickness={0.12}
        rippleIntensityScale={1.5}
        liquid={false}
        liquidStrength={0.12}
        liquidRadius={1.2}
        liquidWobbleSpeed={5}
        speed={0.5}
        edgeFade={0.25}
        transparent
      />
    </div>
  );
}
