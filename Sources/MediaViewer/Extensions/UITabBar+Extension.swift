import UIKit

extension UITabBar {
    func snapshotViewWithFrame(afterScreenUpdates: Bool) -> UIView? {
        guard let snapshot = snapshotView(afterScreenUpdates: afterScreenUpdates) else {
            return nil
        }

        snapshot.frame = frame
        snapshot.layer.zPosition = .greatestFiniteMagnitude

        return snapshot
    }
}
