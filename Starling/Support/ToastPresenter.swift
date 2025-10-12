//
//  ToastPresenter.swift
//  Starling
//
//  Created by ChatGPT on 11/24/23.
//

import Foundation

@MainActor
final class ToastPresenter {
    private let appState: AppState
    private var toastTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
    }

    func show(message: String, delay: TimeInterval = 0.0, duration: TimeInterval = 2.0) {
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            }
            guard !Task.isCancelled else { return }

            self.appState.showToast(message: message)

            guard duration > 0 else { return }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))
            guard !Task.isCancelled else { return }
            self.resetIfShowingToast()
        }
    }

    func cancel(resetToIdle: Bool = false) {
        toastTask?.cancel()
        toastTask = nil
        if resetToIdle {
            resetIfShowingToast()
        }
    }

    private func resetIfShowingToast() {
        if case .toast = appState.phase {
            appState.resetToIdle()
        }
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }
}
