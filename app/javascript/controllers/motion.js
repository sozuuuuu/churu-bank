// 「視差効果を減らす」設定のときは、アニメーションを控える
export const prefersReducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches

// 要素のまわりに星をいくつか、ぱっと光らせて消す（Web Animations API）
export function kira(element, count = 5) {
  if (prefersReducedMotion()) return
  const rect = element.getBoundingClientRect()
  const colors = ["", "sky", "pink"]
  for (let i = 0; i < count; i++) {
    const star = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    star.setAttribute("viewBox", "0 0 20 20")
    star.setAttribute("aria-hidden", "true")
    star.classList.add("kira")
    if (colors[i % 3]) star.classList.add(colors[i % 3])
    star.innerHTML = '<path d="M10 1 l2.4 6.6 l6.6 2.4 l-6.6 2.4 l-2.4 6.6 l-2.4 -6.6 l-6.6 -2.4 l6.6 -2.4 z"/>'
    const angle = (Math.PI * 2 * i) / count - Math.PI / 2
    const r = Math.max(rect.width, rect.height) * 0.62
    star.style.left = `${rect.left + rect.width / 2 + Math.cos(angle) * r}px`
    star.style.top = `${rect.top + rect.height / 2 + Math.sin(angle) * r}px`
    document.body.append(star)
    star.animate(
      [
        { transform: "translate(-50%, -50%) scale(0) rotate(-45deg)" },
        { transform: "translate(-50%, -50%) scale(1.2) rotate(10deg)", offset: 0.45 },
        { transform: "translate(-50%, -50%) scale(0) rotate(30deg)" }
      ],
      { duration: 800, delay: i * 70, easing: "cubic-bezier(.3,1.4,.5,1)", fill: "both" }
    ).finished.then(() => star.remove())
  }
}
