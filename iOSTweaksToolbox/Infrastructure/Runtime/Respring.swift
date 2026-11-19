//
//  Respring.swift
//  iOSTweaksToolbox
//
//  免越狱注销。原理：在 WKWebView 里渲染一个极端耗显存的页面
//  （500 层 100px backdrop-filter + 10MB 随机内存抖动），
//  把 SpringBoard 的图形上下文压到崩溃，系统自动重启 SpringBoard，
//  效果等同「注销」。原作 @neonmodder123，Swift 封装 @skadz108。
//
//  不使用任何私有 API，不写系统文件，失败最多是页面卡一下。
//

import SwiftUI
import WebKit

enum RespringDocument {
    static let html = """
    <!DOCTYPE html>
    <html>
        <body style="margin:0;background:#000;">
            <iframe id="frame" srcdoc="" sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe>
            <script>
                const frame = document.getElementById('frame');
                const payload = `
                    <html>
                    <body style="margin:0;overflow:hidden;background:#000;">
                        <script>
                            const container = document.createElement('div');
                            container.style.cssText = 'perspective: 1px; perspective-origin: 9999999% 9999999%;';
                            document.body.appendChild(container);

                            for (let i = 0; i < 500; i++) {
                                let d = document.createElement('div');
                                d.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(100px); -webkit-backdrop-filter: blur(100px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';
                                container.appendChild(d);
                            }

                            setInterval(() => {
                                navigator.share({ title: 'R', text: 'R'.repeat(100000) }).catch(() => {});
                                let x = new Uint8Array(1024 * 1024 * 10);
                                crypto.getRandomValues(x);
                            }, 0);
                        <\/script>
                    </body>
                    </html>
                `;
                frame.srcdoc = payload;
            </script>
        </body>
    </html>
    """
}

struct RespringView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(RespringDocument.html, baseURL: nil)
    }
}

struct RespringOverlay: ViewModifier {
    @Binding var isActive: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                RespringView()
                    .brightness(-1.0)
                    .ignoresSafeArea()
            }
        }
    }
}

extension View {
    func respringOverlay(_ isActive: Binding<Bool>) -> some View {
        modifier(RespringOverlay(isActive: isActive))
    }
}
