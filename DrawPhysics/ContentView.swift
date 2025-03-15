//
//  ContentView.swift
//  DrawPhysics
//
//  Created by Chitransh on 17/08/26.
//

import SwiftUI

struct ContentView: View {
    // Inject the real store
    @State private var store: SolutionStore?
    
    var body: some View {
        Group {
            if let store = store {
                HomeView(store: store)
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            do {
                store = try SolutionStore()
            } catch {
                print("Failed to init store: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
