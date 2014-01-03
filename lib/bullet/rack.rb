module Bullet
  class Rack
    include Dependency

    def initialize(app)
      @app = app
    end

    def call(env)
      @env = env
      return @app.call(env) unless Bullet.enable?
      Bullet.start_request
      status, headers, response = @app.call(env)
      return [status, headers, response] if file?(headers) || empty?(response)

      response_body = nil
      if Bullet.notification?
        if status == 200 && !response_body(response).frozen? && html_request?(headers, response)
          response_body = response_body(response) << Bullet.gather_inline_notifications
          add_footer_note(response_body) if Bullet.add_footer
          headers['Content-Length'] = response_body.bytesize.to_s
        end
        Bullet.perform_out_of_channel_notifications(env)
      end
      Bullet.end_request
      [status, headers, response_body ? [response_body] : response]
    end

    # fix issue if response's body is a Proc
    def empty?(response)
      # response may be ["Not Found"], ["Move Permanently"], etc.
      if rails?
        (response.is_a?(Array) && response.size <= 1) ||
          !response.respond_to?(:body) ||
          !response_body(response).respond_to?(:empty?) ||
          response_body(response).empty?
      else
        body = response_body(response)
        body.nil? || body.empty?
      end
    end

    def add_footer_note(response_body)
      response_body << "<div #{footer_div_style}>#{headline}#{bullet_errors}</div>"
    end

    # if send file?
    def file?(headers)
      headers["Content-Transfer-Encoding"] == "binary"
    end

    def html_request?(headers, response)
      headers['Content-Type'] && headers['Content-Type'].include?('text/html') &&
                                 response_body(response).include?("<html")
    end

    def response_body(response)
      if rails?
        Array === response.body ? response.body.first : response.body
      else
        response.first
      end
    end

    private

    def headline
<<EOF
<h3>
  Errors:
  <small style='margin-left:20px;'>
    <a href='#{file_path}'>Open File</a>
  </small>
</h3>
EOF
    end

    def bullet_errors
      Bullet.footer_info.uniq.join("<br>")
    end

    def footer_div_style
<<EOF
style="position: fixed;bottom:0;right:0;width:100%;z-index:2000;
padding:14px;background:rgba(0,0,0,.8);color:#fff;line-height:2;"
EOF
    end
    
    def editor
      case Bullet.editor
      when :sublime then
        "subl"
      when :textmate then
        "txmt"
      when :emacs then
        "emacs"
      when :macvim then
        "mvim"
      else
        "txmt"
      end
    end

    def file_path
      path = Rails.root.join('app/controllers', "#{controller.underscore}.rb")
      "#{editor}://open?url=file://#{path}"
    end

    def controller
      @env['action_controller.instance'].class.name
    end
  end
end
