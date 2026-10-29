import SwiftUI
import UIKit

/// 全屏游戏容器。横向、无状态栏、自动保持屏幕常亮。
struct GameView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let version: GameVersion

    @State private var url: URL?
    @State private var reloadToken = 0
    @State private var isLoading = true
    @State private var errorText = ""
    @State private var controlsVisible = true
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let target = url {
                WebViewContainer(url: target,
                                 reloadToken: reloadToken,
                                 isLoading: $isLoading,
                                 errorText: $errorText)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("正在启动本地客户端服务…")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Text(model.serverStatus)
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }

            if isLoading && url != nil {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("载入客户端…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(18)
                .background(Color.black.opacity(0.6))
                .cornerRadius(14)
            }

            if !errorText.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorText)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                    Button("重试") {
                        reloadToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(maxWidth: 460)
                .background(Color.black.opacity(0.85))
                .cornerRadius(16)
            }

            if controlsVisible {
                VStack {
                    HStack(spacing: 10) {
                        controlButton("power", tint: .red) {
                            dismiss()
                        }
                        controlButton("arrow.clockwise", tint: .white) {
                            reloadToken += 1
                        }
                        controlButton("gearshape", tint: .white) {
                            controlsVisible = true
                            hideWorkItem?.cancel()
                        }
                        Spacer()
                        Text(version.title)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    Spacer()
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            prepare()
            scheduleAutoHide()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: model.port) { _, _ in
            if url == nil { prepare() }
        }
    }

    private func controlButton(_ systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .padding(9)
                .background(Color.black.opacity(0.45))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func prepare() {
        url = model.playURL(for: version)
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { controlsVisible = false }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }
}
