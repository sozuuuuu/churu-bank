import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// 残高。動くのは出来事のときだけ: 最初はそのまま出し、morph（Turbo の refresh）で
// data-count-up-amount-value が変わったら、前の値から新しい値まで数える。
// 数字は number ターゲット（単位は別の要素）。ターゲットがなければ要素に「数字 + 単位」を書く
export default class extends Controller {
  static targets = ["number"]
  static values = { amount: Number, unit: String, duration: { type: Number, default: 900 } }

  amountValueChanged(amount) {
    const first = this.shown === undefined
    const from = first ? amount : this.shown
    this.shown = amount
    if (first || from === amount) return this.#render(amount)

    this.#bump(amount > from ? "up" : "down")
    this.#animate(from, amount)
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }

  #animate(from, to) {
    cancelAnimationFrame(this.frame)
    if (prefersReducedMotion()) return this.#render(to)

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
    const text = n.toLocaleString("ja-JP")
    if (this.hasNumberTarget) this.numberTarget.textContent = text
    else this.element.textContent = `${text}${this.unitValue}`
  }

  // 増えたら「ぽよん」、減ったら「しゅん」（CSS の .up / .down）
  #bump(direction) {
    this.element.classList.remove("up", "down")
    void this.element.offsetWidth // アニメーションをやり直すため
    this.element.classList.add(direction)
  }
}
