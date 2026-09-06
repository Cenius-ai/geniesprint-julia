# ---------------------------------------------------------------------------
# Web layer: security response headers, styled-404 pre-response hook, and the
# boot entrypoint (migrate + seed + serve, bound to 0.0.0.0:$PORT).
# ---------------------------------------------------------------------------

import HTTP

"""Default security headers applied to every dynamic response."""
function security_headers!(resp::HTTP.Response)::HTTP.Response
    headers = [
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "DENY",
        "Referrer-Policy" => "strict-origin-when-cross-origin",
        "Permissions-Policy" => "camera=(), microphone=(), geolocation=()",
        "Content-Security-Policy" => "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
    ]
    for (k, v) in headers
        if !any(h -> first(h) == k, resp.headers)
            push!(resp.headers, SubString(k) => SubString(v))
        end
    end
    resp
end

"""Pre-response hook: adds security headers + rewrites framework 404s to a styled page."""
function genieteam_pre_response_hook(req, res, params_collection)
    res = security_headers!(res)

    if res.status == 404
        body = layout_standalone(
            status = 404,
            title = "Page not found",
            message = "We couldn't find the page you were looking for.",
        )
        resp2 = Genie.Renderer.respond(body, :html, 404)
        # Carry over cookies that were attached to the original response (rare for 404s).
        attach_session_cookie!(resp2)
        res = resp2
    end

    (req, res, params_collection)
end

const _HOOKS_INSTALLED = Ref(false)

"""Registers the pre-response hook exactly once per process."""
function install_web_hooks!()
    _HOOKS_INSTALLED[] && return nothing
    push!(Genie.Router.pre_response_hooks, genieteam_pre_response_hook)
    _HOOKS_INSTALLED[] = true
    nothing
end

"""Full startup: DB connect + migrate + seed-if-empty, hooks, routes, server."""
function boot()
    prepare_database!()

    Genie.config.server_host = server_host()
    Genie.config.server_port = server_port()
    Genie.config.server_document_root = static_document_root()
    Genie.config.run_as_server = true
    Genie.Secrets.secret_token!(app_secret())

    install_web_hooks!()
    register_routes!()

    host = Genie.config.server_host
    port = Genie.config.server_port
    @info "GenieTeam boot complete — listening on $host:$port (document root: $(Genie.config.server_document_root))"

    # Blocks forever (run_as_server = true). Ctrl+C stops the server.
    Genie.Server.up(port, host)
end
