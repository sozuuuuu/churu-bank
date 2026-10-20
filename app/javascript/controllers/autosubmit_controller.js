import { Controller } from "@hotwired/stimulus"

// 入力が変わったらフォームを送る（Turbo がフォームの data-turbo-frame に結果を差し込む）
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
