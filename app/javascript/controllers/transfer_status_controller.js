import { Controller } from "@hotwired/stimulus"

// 振込の状態。ジョブが「処理中」→「完了」に進めると、morph で値が変わるのでお祝いを頼む
export default class extends Controller {
  static values = { status: String }

  statusValueChanged(status, previous) {
    if (previous !== "requested") return

    if (status === "completed") {
      this.dispatch("settled", { detail: { origin: this.element, message: "振込が届いたにゃ！", emojis: ["🎉", "🐟", "🐾", "✨"] } })
    } else if (status === "failed") {
      this.dispatch("settled", { detail: { origin: this.element, message: "振込が戻ってきたにゃ…", emojis: ["💧"] } })
    }
  }
}
