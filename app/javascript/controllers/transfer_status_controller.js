import { Controller } from "@hotwired/stimulus"

// 振込の状態（通帳の「振込（送金）」の行）。ジョブが「処理中」（保留を通したときは「保留中」から）→「完了」に進めると、
// morph で値が変わるので celebrate に演出を頼む（完了 → 振込完了の画面、戻ってきた → しょんぼり）。
// 振り込んだ直後のページ（just-created）で、描いた時点でもう完了していたときも演出する。
// 取消・差し止めは自分（か行員）がしたことなので何も出さない
export default class extends Controller {
  static values = {
    status: String, justCreated: Boolean,
    to: String, amount: Number, memo: String, at: String, balance: Number
  }

  connect() {
    if (!this.justCreatedValue) return
    if (this.statusValue === "completed") this.#announce("completed")
    else if (this.statusValue === "requested") this.#recheck(4)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  statusValueChanged(status, previous) {
    if (previous === "requested" || previous === "held") this.#announce(status)
  }

  // 振り込んだ直後の「処理中」。ジョブの refresh の配信は、自分が出したリクエストのものとして無視されることがあるので、
  // 少し待ってから自分で描き直す（morph。完了していれば statusValueChanged が演出を出す）
  #recheck(times) {
    this.timer = setTimeout(() => {
      if (this.statusValue !== "requested") return
      window.Turbo?.session.refresh(location.href)
      if (times > 1) this.#recheck(times - 1)
    }, 1500)
  }

  #announce(status) {
    const amount = this.amountValue.toLocaleString("ja-JP")
    if (status === "completed") {
      const meta = [this.memoValue && `メモ: ${this.memoValue}`, this.atValue,
                    `残高 ${this.balanceValue.toLocaleString("ja-JP")} ちゅ〜る`].filter(Boolean).join(" ・ ")
      this.dispatch("settled", {
        detail: {
          text: `とどいたにゃ！ ${this.toValue}に ${amount} ちゅ〜る、ちゃんと届けたにゃ。`,
          face: "happy", bounce: true,
          hooray: { to: this.toValue, amount: this.amountValue, meta }
        }
      })
    } else if (status === "failed") {
      this.dispatch("settled", {
        detail: { text: `振込が戻ってきたにゃ… ${amount} ちゅ〜るは口座に戻してあるにゃ。`, face: "sad" }
      })
    }
  }
}
