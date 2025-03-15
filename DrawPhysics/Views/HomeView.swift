import SwiftUI

struct HomeView: View {
    let store: SolutionStore
    @State private var completedLevelIDs: Set<String> = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
                    ForEach(AuthoredLevels.all, id: \.id) { level in
                        NavigationLink(destination: PlayView(session: GameSession(level: level, store: store))) {
                            VStack {
                                LevelThumbnailView(level: level)
                                    .frame(height: 200)
                                    .overlay(
                                        Group {
                                            if completedLevelIDs.contains(level.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.title2)
                                                    .padding(8)
                                                    .background(Circle().fill(Color.white))
                                                    .padding(8)
                                            }
                                        }
                                        , alignment: .topTrailing
                                    )
                                
                                Text(level.title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Levels")
            .onAppear {
                loadProgress()
            }
        }
    }
    
    private func loadProgress() {
        // Query the store for each level
        var completed: Set<String> = []
        for level in AuthoredLevels.all {
            if let records = try? store.records(forLevel: level.id), records.contains(where: { $0.didReachGoal }) {
                completed.insert(level.id)
            }
        }
        completedLevelIDs = completed
    }
}

#Preview {
    HomeView(store: try! SolutionStore(inMemory: true))
}
