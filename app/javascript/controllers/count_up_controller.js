import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// 金額をカウントアップで見せる。最初は 0 から、morph（Turbo の refresh）で
// data-count-up-amount-value が変わったら、前の値から新しい値まで数える
export default class extends Controller {
  static values = { amount: Number, unit: String, duration: { type: Number, default: 900 } }

  amountValueChanged(amount) {
    const first = this.shown === undefined
    const from = first ? 0 : this.shown
    this.shown = amount
    if (!first && from !== amount) this.#bump(amount > from ? "up" : "down")
    this.#animate(from, amount)
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }

  #animate(from, to) {
    cancelAnimationFrame(this.frame)
    if (prefersReducedMotion() || from === to) return this.#render(to)

    const start = performance.now()
    const tick = (now) => {
      const t = Math.min((now - start) / this.durationValue, 1)
      const eased = 1 - Math.pow(1 - t, 3) // easeOutCubic
      this.#render(Math.round(from + (to - from) * eased))
      if (t < 1) this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }

  #render(n) {
    this.element.textContent = `${n.toLocaleString("ja-JP")}${this.unitValue}`
  }

  // 増えたら「ぽよん」、減ったら「しゅん」（CSS の .up / .down）
  #bump(direction) {
    this.element.classList.remove("up", "down")
    void this.element.offsetWidth // アニメーションをやり直すため
    this.element.classList.add(direction)
  }
}
