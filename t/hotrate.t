# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

#no_diff();
#no_long_string();

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict store 1m;
_EOC_

no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local hotrate = require "resty.hotrate"
            ngx.shared.store:flush_all()
            local hr = hotrate.new("store", 100, 100, 1000)
            local uri = ngx.var.uri

            local s, e
            for i = 1, 200 do
                local hot = hr:coming(uri)
                if hot then
                    if not s then
                        s = i
                    end
                    ngx.sleep(0.05)
                else
                    if s and not e then
                        e = i
                    end
                    ngx.sleep(0.001)
                end
            end
            ngx.say("hot num: ", e - s)
        }
    }
--- request
    GET /t
--- response_body_like eval
qr/^hot num: 2[4-6]$/
--- no_error_log
[error]
[lua]
