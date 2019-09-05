# frozen_string_literal: true

require_dependency 'barong/authorize'

# Rails Metal base controller to manage AuthZ story
class AuthorizeController < ActionController::Metal
  include AbstractController::Rendering
  use ActionDispatch::Session::CookieStore

  # /api/v2/auth endpoint
  def authorize
    req = Barong::Authorize.new(request, params[:path]) # initialize params of request
    # checks if request is blacklisted
    return access_error!('authz.permission_denied', 401) if req.restricted?('block')

    return access_error!('authz.csrf_protection', 401) unless csrf_token_validate?

    response.status = 200
    return if req.restricted?('pass') # check if request is whitelisted
    request.session_options[:skip] = true # false by default (always sets set-cookie header)

    response.headers['Authorization'] = req.auth # sets bearer token
  rescue Barong::Authorize::AuthError => e # returns error from validations
    response.body = e.message
    response.status = e.code
  end

  private

  def session
    request.session
  end

  # error for blacklisted routes
  def access_error!(text, code)
    response.status = code
    response.body = { 'errors': [text] }.to_json
  end

  def csrf_token_validate?
    if request.get? || request.head? || (request.headers.key?('X-CSRF-Auth') &&
       request.headers['X-CSRF-Auth'] == Rails.cache.read(session[:uid]))
      return true
    end

    return false
  end
end
