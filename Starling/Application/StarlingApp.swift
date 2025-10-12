//
//  StarlingApp.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import SwiftUI

@main
struct StarlingApp: App {
    @StateObject private var preferences = PreferencesStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(preferences)
        }
    }
}
