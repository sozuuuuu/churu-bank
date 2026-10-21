import { Controller } from "@hotwired/stimulus"

// 通帳に、morph で新しく入ってきた行だけ「ぽん」と出す（CSS の .arrived）。
// 行の種類（data-kind）に合わせて arrival:arrived を投げ、celebrate にねこのセリフを頼む
// （入金 → うれしい、組戻し・取消で引かれた → しょんぼり）。
// morph は並べ替えのために既存の行を入れ直すこともあるので、見たことのある id は数えない
export default class extends Controller {
  connect() {
    this.seen = new Set([...this.element.children].map((row) => row.id))
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE || !node.id || this.seen.has(node.id)) continue
          this.seen.add(node.id)
          this.#arrived(node)
        }
      }
    })
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  #arrived(row) {
    row.classList.add("arrived")
    row.addEventListener("animationend", () => row.classList.remove("arrived"), { once: true })
    const line = lineFor(row.dataset.kind, Math.abs(Number(row.dataset.amount)).toLocaleString("ja-JP"))
    if (line) this.dispatch("arrived", { detail: line })
  }
}

function lineFor(kind, amount) {
  switch (kind) {
    case "deposit":
    case "transfer_in":
    case "withdrawal_reversal":
      return { text: `ちゅ〜るが届いたにゃ！ ${amount} ちゅ〜る増えたにゃ。`, face: "happy", bounce: true }
    case "interest":
      return { text: `利息がついたにゃ！ ${amount} ちゅ〜る増えたにゃ。`, face: "happy", bounce: true }
    case "transfer_refund":
      return { text: `振込のお金が戻ってきたにゃ。${amount} ちゅ〜る、口座に戻ったにゃ。`, face: "normal" }
    case "transfer_reversal":
      return { text: `組戻しで ${amount} ちゅ〜る引き戻されたにゃ…`, face: "sad" }
    case "deposit_reversal":
      return { text: `入金が取り消されたにゃ… ${amount} ちゅ〜る減ったにゃ。`, face: "sad" }
    case "withdrawal":
      return { text: `${amount} ちゅ〜る出金したにゃ。`, face: "normal" }
    default:
      return null
  }
}
