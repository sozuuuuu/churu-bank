import { Controller } from "@hotwired/stimulus"

// ページの頭のお知らせの吹き出し（packs/notices の notices/inbox/_board）。
// 新しいお知らせが refresh（morph）で入ってきたら、ねこのセリフ窓で知らせる（cat:say。重要なものはびっくり顔）。
// 新しく入った吹き出しには .is-fresh を付けて、CSS で「ぽん」と出す
export default class extends Controller {
  connect() {
    this.seen = new Set(this.#ids())
    this.observer = new MutationObserver(() => this.#check())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  #ids() {
    return [...this.element.querySelectorAll("[data-notice-id]")].map((el) => el.dataset.noticeId)
  }

  #check() {
    const fresh = this.#ids().filter((id) => !this.seen.has(id))
    if (fresh.length === 0) return
    fresh.forEach((id) => {
      this.seen.add(id)
      this.element.querySelector(`[data-notice-id="${id}"]`)?.classList.add("is-fresh")
    })

    const important = fresh.some((id) => this.element.querySelector(`[data-notice-id="${id}"].is-important`))
    const detail = important
      ? { text: "重要なお知らせが届いたにゃ！ 上の吹き出しを開いてにゃ。", face: "surprised" }
      : { text: "銀行からお知らせが届いたにゃ。上の吹き出しから読めるにゃ。", face: "normal" }
    window.dispatchEvent(new CustomEvent("cat:say", { detail }))
  }
}
