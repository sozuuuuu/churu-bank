import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import consumer from "controllers/counter/consumer"

// 窓口チャット（利用者の counter/tickets/_chat と、行員の counter_admin/tickets/show）。Counter::ChatChannel を購読する。
//   ブラウザ → サーバー: perform("speak", { body }) / perform("speak", { kind: "withdrawal_guide" }) / perform("typing")
//   サーバー → ブラウザ: message（発言を足す）/ typing（相手の「入力中…」）/ presence（相手の在席）/ closed（終わった）/ error
// role（customer / staff）は「どちらとして入るか」。サーバーが接続の持ち主で確かめる
const TYPING_INTERVAL = 1500 // 「入力中」を送るのは 1.5 秒に1回まで
const TYPING_SHOWN = 3000 // 相手の「入力中…」は、最後に届いてから 3 秒で消す

export default class extends Controller {
  static targets = ["log", "input", "typing", "presence", "presenceText", "status", "form", "guide"]
  static values = { ticketId: Number, role: String, presentText: String, absentText: String }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "Counter::ChatChannel", ticket_id: this.ticketIdValue, role: this.roleValue },
      {
        connected: () => this.#status(""),
        disconnected: () => this.#status("接続が切れました。つなぎ直しています…"),
        rejected: () => this.#status("このチャットには入れません。"),
        received: (data) => this.#received(data)
      }
    )
    this.#scroll()
  }

  disconnect() {
    this.subscription?.unsubscribe()
    clearTimeout(this.typingTimer)
  }

  send(event) {
    event.preventDefault()
    const body = this.inputTarget.value.trim()
    if (body === "") return
    this.subscription.perform("speak", { body })
    this.inputTarget.value = ""
    this.lastTyping = 0
  }

  // Enter で送る（Shift+Enter は改行。日本語の変換中の Enter は送らない）
  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing || event.keyCode === 229) return
    this.formTarget.requestSubmit()
  }

  typing() {
    const now = Date.now()
    if (this.inputTarget.value.trim() === "" || now - (this.lastTyping ?? 0) < TYPING_INTERVAL) return
    this.lastTyping = now
    this.subscription.perform("typing")
  }

  // 行員だけ: 出金依頼の画面への案内を出す（利用者の画面には自分の口座の「出金の依頼」へのリンクが付く）
  guideWithdrawal() {
    this.subscription.perform("speak", { kind: "withdrawal_guide" })
  }

  #received(data) {
    switch (data.type) {
      case "message": return this.#message(data)
      case "typing": return this.#typing(data)
      case "presence": return this.#presence(data)
      case "closed": return this.#closed(data)
      case "error": return this.#status(data.message)
    }
  }

  #message(data) {
    if (this.logTarget.querySelector(`[data-message-id="${data.id}"]`)) return // つなぎ直しなどで2回届いても1回だけ
    const mine = data.role === this.roleValue
    const item = document.createElement("li")
    item.className = `chat-message ${mine ? "is-mine" : "is-theirs"} is-${data.role} is-fresh`
    item.dataset.messageId = data.id
    item.append(this.#el("span", "chat-name", data.name), this.#el("p", "chat-body", data.body))
    if (data.kind === "withdrawal_guide" && this.hasGuideTarget) item.append(this.guideTarget.content.cloneNode(true))
    item.append(this.#el("time", "chat-time", data.at))
    this.logTarget.append(item)
    if (!mine) {
      this.#hideTyping()
      if (this.roleValue === "customer" && data.kind === "withdrawal_guide") {
        this.#say({ text: "出金の依頼の画面へのボタンが届いたにゃ。押すと口座のページが開くにゃ。", face: "normal" })
      }
    }
    this.#scroll()
  }

  #typing({ role }) {
    if (role === this.roleValue) return
    this.typingTarget.hidden = false
    clearTimeout(this.typingTimer)
    this.typingTimer = setTimeout(() => this.#hideTyping(), TYPING_SHOWN)
  }

  #hideTyping() {
    clearTimeout(this.typingTimer)
    this.typingTarget.hidden = true
  }

  #presence({ role, present }) {
    if (role === this.roleValue || !this.hasPresenceTarget) return
    this.presenceTarget.classList.toggle("is-present", present)
    this.presenceTextTarget.textContent = present ? this.presentTextValue : this.absentTextValue
  }

  #closed({ by }) {
    this.subscription?.unsubscribe()
    this.subscription = null
    this.formTarget.querySelectorAll("textarea, button").forEach((el) => (el.disabled = true))
    this.#hideTyping()
    if (this.roleValue === "customer") {
      const text = by === "staff" ? "おつかれさまでしたにゃ。またいつでも札をとってにゃ。" : "札を返したにゃ。またいつでも来てにゃ。"
      this.#say({ text, face: "happy", bounce: by === "staff" })
      const frame = this.element.closest("turbo-frame")
      if (frame) frame.src ? frame.reload() : (frame.src = window.location.href)
    } else {
      this.#status("このチャットは終わりました。")
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  #status(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  #say(detail) {
    window.dispatchEvent(new CustomEvent("cat:say", { detail }))
  }

  #scroll() {
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  // 文字はいつも textContent で入れる（発言に HTML が入っていても、そのまま文字として出す）
  #el(tag, className, text) {
    const el = document.createElement(tag)
    el.className = className
    el.textContent = text
    return el
  }
}
