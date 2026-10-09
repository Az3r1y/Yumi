import SwiftUI

/// Every feature that can be turned on or off, by theme (`Feature`).
struct FeaturesSettings: View {
    var body: some View {
        Form {
            ForEach(Feature.Group.allCases) { group in
                Section(group.title) {
                    ForEach(Feature.allCases.filter { $0.group == group }) { FeatureToggle(feature: $0) }
                }
            }
        }
    }
}

private struct FeatureToggle: View {
    let feature: Feature
    @AppStorage private var on: Bool

    init(feature: Feature) {
        self.feature = feature
        _on = AppStorage(wrappedValue: feature.defaultOn, feature.key)
    }

    var body: some View {
        Toggle(isOn: $on) {
            Text(feature.title)
            Text(feature.detail)
        }
    }
}
