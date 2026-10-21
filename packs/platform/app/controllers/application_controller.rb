# すべての画面のコントローラの土台。ログインは各パックのベースで include する（行員の画面は StaffAuthentication、利用者の画面は CustomerAuthentication）
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
