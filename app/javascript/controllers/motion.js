// 「視差効果を減らす」設定のときは、アニメーションを控える
export const prefersReducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches
