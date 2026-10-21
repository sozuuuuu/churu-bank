import { Controller } from "@hotwired/stimulus"

// 振込の状態。ジョブが「処理中」（保留を通したときは「保留中」から）→「完了」に進めると、
// morph で値が変わるのでお祝いを頼む。取消・差し止めは自分（か行員）がしたことなので何も出さない
export default class extends Controller {
  static values = { status: String }

  statusValueChanged(status, previous) {
    if (previous !== "requested" && previous !== "held") return

    if (status === "completed") {
      this.dispatch("settled", { detail: { origin: this.element, message: "振込が届いたにゃ！", emojis: ["🎉", "🐟", "🐾", "✨"] } })
    } else if (status === "failed") {
      this.dispatch("settled", { detail: { origin: this.element, message: "振込が戻ってきたにゃ…", emojis: ["💧"] } })
    }
  }
}
