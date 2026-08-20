import DiscleanKit
import SwiftUI

@main
struct DiscleanApp: App {
    init() {
        // クラウド未ダウンロードのファイルを、走査で実体化させない。
        DatalessPolicy.disableMaterialization()
    }

    var body: some Scene {
        WindowGroup("ディスクリン") {
            RootView()
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}
