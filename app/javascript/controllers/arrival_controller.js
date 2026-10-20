import { Controller } from "@hotwired/stimulus"

// 通帳に、morph で新しく入ってきた行だけ「ふわっ」と出す（CSS の .arrived）。
// 入金の行なら arrival:arrived を投げて、celebrate にお祝いしてもらう。
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
    if (row.dataset.incoming === "true") {
      this.dispatch("arrived", { detail: { origin: row, message: "ちゅ〜るが届いたにゃ！", emojis: ["🐟", "✨", "💕"] } })
    }
  }
}
