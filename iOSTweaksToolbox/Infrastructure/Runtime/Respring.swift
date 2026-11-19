//
//  Respring.swift
//  iOSTweaksToolbox
//
//  免越狱注销的尝试实现 + 失败兜底。
//
//  必须说清楚的事实：iOS 上 SpringBoard 的重启由 launchd 控制，第三方
//  App 没有任何公开或稳定的私有接口能触发它。社区流传的 WKWebView
//  显存压榨法（@neonmodder123）在部分系统版本上能把渲染服务压垮从而
//  连带重启 SpringBoard，但不保证；iOS 27 上实测多数情况只是本 App
//  自己变黑。所以这里把它做成「尝试 + 超时兜底 + 明确失败告知」，
//  绝不假装成功。
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
                            for (let i = 0; i < 600; i++) {
                                let d = document.createElement('div');
                                d.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(120px); -webkit-backdrop-filter: blur(120px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';
                                container.appendChild(d);
                            }
                            setInterval(() => {
                                let x = new Uint8Array(1024 * 1024 * 16);
                                crypto.getRandomValues(x);
                            }, 0);
                        ${'</scr' + 'ipt>'}
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

/// 注销遮罩。带超时兜底：超时后自动收起，并告知用户这次没成功。
struct RespringOverlay: ViewModifier {
    @Binding var isActive: Bool
    @Binding var failed: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        RespringView().ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("正在尝试注销…").font(.footnote).foregroundStyle(.white.opacity(0.7))
                            Text("如果 8 秒后仍停在这里，说明自动注销未生效")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                            // 还活着 = SpringBoard 没重启 = 这次失败
                            if isActive {
                                isActive = false
                                failed = true
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func respringOverlay(_ isActive: Binding<Bool>, failed: Binding<Bool>) -> some View {
        modifier(RespringOverlay(isActive: isActive, failed: failed))
    }
}
