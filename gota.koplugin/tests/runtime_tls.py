#!/usr/bin/env python3
"""Check Gota TLS against real KOReader LuaSec using a local HTTPS server.

Run: python3 tests/runtime_tls.py /absolute/path/to/koreader-runtime
The runtime folder must contain luajit and common/ssl/https.lua. Requires
Python 3 and OpenSSL 1.1.1 or newer in PATH. All certificates and keys are
synthetic, created in an isolated temporary folder, and deleted afterward.
No account, token, external network, or changes to KOReader are needed.
"""

import argparse
import http.server
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.received_requests += 1
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


LUA_CHECK = """package.path = 'common/?.lua;' .. package.path
package.cpath = 'common/?.so;' .. package.cpath
package.preload.gota_gettext=function() return function(v) return v end end
local TLS=dofile(arg[1] .. '/gota_tls.lua')
local settings={ getTLSCAFile=function() return arg[2] end }
local tls=TLS:new(settings)
local chunks={}
local ok,status=tls:request({ url=arg[3], sink=require('ltn12').sink.table(chunks), redirect=false })
print(arg[4], 'result='..tostring(ok), 'status='..tostring(status),
    'verified='..tostring(tls:getSecurityInfo().validation_observed),
    'body_bytes='..#table.concat(chunks))
if arg[4]=='valid' then
    assert(ok==1 and status==200 and tls:getSecurityInfo().validation_observed)
    assert(table.concat(chunks)=='ok')
else
    assert(ok==nil and #chunks==0 and not tls:getSecurityInfo().validation_observed)
    if arg[4]=='hostname mismatch' then assert(tostring(status):find('hostname',1,true)) end
    if arg[4]=='untrusted CA' then assert(tostring(status):find('certificate verify failed',1,true)) end
end
"""


def check_runtime(runtime, openssl_binary):
    plugin = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="gota-tls-runtime-") as directory:
        root = Path(directory)

        def openssl(*args):
            result = subprocess.run(
                [openssl_binary, *args], cwd=root,
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
            )
            if result.returncode:
                raise RuntimeError(result.stderr.strip())

        for name in ("ca", "other-ca"):
            openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-subj", f"/CN=Gota test {name}",
                    "-addext", "basicConstraints=critical,CA:TRUE",
                    "-keyout", f"{name}.key", "-out", f"{name}.pem")

        for name, hostname in (("valid", "localhost"), ("wrong", "other.invalid")):
            openssl("req", "-newkey", "rsa:2048", "-nodes", "-subj", f"/CN={hostname}",
                    "-keyout", f"{name}.key", "-out", f"{name}.csr")
            (root / f"{name}.ext").write_text(
                f"subjectAltName=DNS:{hostname}\nextendedKeyUsage=serverAuth\n"
                "basicConstraints=CA:FALSE\n", encoding="utf-8",
            )
            openssl("x509", "-req", "-in", f"{name}.csr", "-CA", "ca.pem",
                    "-CAkey", "ca.key", "-CAcreateserial", "-days", "1",
                    "-extfile", f"{name}.ext", "-out", f"{name}.pem")

        lua_check = root / "check.lua"
        lua_check.write_text(LUA_CHECK, encoding="utf-8")
        cases = (
            ("valid", "ca", "valid"),
            ("wrong", "ca", "hostname mismatch"),
            ("valid", "other-ca", "untrusted CA"),
        )
        for certificate, authority, label in cases:
            server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
            server.received_requests = 0
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(root / f"{certificate}.pem", root / f"{certificate}.key")
            server.socket = context.wrap_socket(server.socket, server_side=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                subprocess.run(
                    [str(runtime / "luajit"), str(lua_check), str(plugin),
                     str(root / f"{authority}.pem"),
                     f"https://localhost:{server.server_port}/", label],
                    cwd=runtime, check=True, timeout=20,
                )
                expected_requests = 1 if label == "valid" else 0
                assert server.received_requests == expected_requests, (
                    f"{label}: expected {expected_requests} HTTP requests, "
                    f"received {server.received_requests}"
                )
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)
        print("3 native TLS checks passed; rejected certificates sent no HTTP request")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path, help="KOReader runtime/build output folder")
    args = parser.parse_args()
    runtime = args.runtime.expanduser().resolve()
    if not (runtime / "luajit").is_file() or not (runtime / "common/ssl/https.lua").is_file():
        parser.error("runtime must contain luajit and common/ssl/https.lua")
    openssl_binary = shutil.which("openssl")
    if not openssl_binary:
        parser.error("OpenSSL 1.1.1 or newer is required in PATH")
    check_runtime(runtime, openssl_binary)


if __name__ == "__main__":
    main()
