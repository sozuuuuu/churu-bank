import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// お祝いの演出: 絵文字の紙吹雪（Web Animations API）、ねこのジャンプ、トースト。
// arrival:arrived / transfer-status:settled を受けて動く。外部ライブラリは使わない
export default class extends Controller {
  static targets = ["toast", "cat"]

  burst({ detail: { origin, message, emojis } }) {
    this.#toast(message)
    if (prefersReducedMotion()) return

    this.#confetti(origin, emojis)
    this.catTargets.forEach((cat) => {
      cat.classList.remove("happy")
      void cat.getBoundingClientRect()
      cat.classList.add("happy")
    })
  }

  #confetti(origin, emojis) {
    const rect = origin.getBoundingClientRect()
    const x = rect.left + rect.width / 2
    const y = rect.top + rect.height / 2

    for (let i = 0; i < 18; i++) {
      const piece = document.createElement("span")
      piece.className = "confetti"
      piece.textContent = emojis[i % emojis.length]
      piece.style.left = `${x}px`
      piece.style.top = `${y}px`
      document.body.append(piece)

      const angle = Math.random() * Math.PI * 2
      const distance = 60 + Math.random() * 110
      const dx = Math.cos(angle) * distance
      const dy = Math.sin(angle) * distance - 60
      piece.animate(
        [
          { transform: "translate(-50%, -50%) scale(.4) rotate(0deg)", opacity: 1 },
          { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) scale(1.1) rotate(${dx}deg)`, opacity: 1, offset: 0.6 },
          { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy + 80}px)) scale(.9) rotate(${dx * 2}deg)`, opacity: 0 }
        ],
        { duration: 1200 + Math.random() * 500, easing: "cubic-bezier(.2,.7,.3,1)" }
      ).finished.then(() => piece.remove())
    }
  }

  #toast(message) {
    if (!this.hasToastTarget) return
    const toast = this.toastTarget
    toast.textContent = message
    toast.classList.add("show")
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => toast.classList.remove("show"), 3000)
  }
}
