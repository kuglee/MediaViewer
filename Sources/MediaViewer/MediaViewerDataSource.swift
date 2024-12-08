//
//  MediaViewerDataSource.swift
//
//
//  Created by Yusaku Nishi on 2023/11/04.
//

import UIKit

/// The object you use to provide data for an media viewer.
@MainActor
public protocol MediaViewerDataSource<MediaIdentifier>: AnyObject {
    
    /// A type representing the unique identifier for media.
    associatedtype MediaIdentifier: Hashable
    
    /// Asks the data source to return all identifiers for media to view in the media viewer.
    /// - Parameter mediaViewer: An object representing the media viewer requesting this information.
    /// - Returns: All identifiers for media to view in the `mediaViewer`.
    func mediaIdentifiers(
        for mediaViewer: MediaViewerViewController
    ) -> [MediaIdentifier]
    
    /// Asks the data source to return media with the specified identifier to view in the media viewer.
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - mediaIdentifier: An identifier for media.
    /// - Returns: Media with `mediaIdentifier` to view in `mediaViewer`.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        mediaWith mediaIdentifier: MediaIdentifier
    ) -> Media
    
    /// Asks the data source to return the transition source view for media currently viewed in the viewer.
    ///
    /// The media viewer uses this view for push or pop transitions.
    /// On the push transition, an animation runs as the image expands from this view. The reverse happens on the pop.
    ///
    /// If `nil`, the animation looks like cross-dissolve.
    ///
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - mediaIdentifier: An identifier for the current viewing media.
    /// - Returns: The transition source view for current media of `mediaViewer`.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        transitionSourceViewForMediaWith mediaIdentifier: MediaIdentifier
    ) -> UIView?
    
    /// Asks the data source to return the transition source image for current media of the viewer.
    ///
    /// The media viewer uses this image for the push transition if needed.
    /// If the viewer has not yet acquired an image asynchronously at the start of the push transition,
    /// the viewer starts a transition animation with this image.
    ///
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - sourceView: A transition source view that is returned from `transitionSourceView(forCurrentMediaOf:)` method.
    /// - Returns: The transition source image for current media of `mediaViewer`.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        transitionSourceImageWith sourceView: UIView?
    ) -> UIImage?
}

// MARK: - Default implementations -

extension MediaViewerDataSource {
    
    public func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        widthToHeightOfMediaWith mediaIdentifier: MediaIdentifier
    ) -> CGFloat? {
        let media = self.mediaViewer(mediaViewer, mediaWith: mediaIdentifier)
        switch media {
        case .image(.sync(let image?)) where image.size.height > 0:
            return image.size.width / image.size.height
        case .image(.sync), .image(.async):
            return nil
        }
    }
    
    public func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        transitionSourceImageWith sourceView: UIView?
    ) -> UIImage? {
        switch sourceView {
        case let sourceImageView as UIImageView:
            return sourceImageView.image
        default:
            return nil
        }
    }
}

// MARK: - Type erasure support -

extension MediaViewerDataSource {
    
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        mediaWith mediaIdentifier: AnyMediaIdentifier
    ) -> Media {
        self.mediaViewer(
            mediaViewer,
            mediaWith: mediaIdentifier.as(MediaIdentifier.self)
        )
    }
    
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        widthToHeightOfMediaWith mediaIdentifier: AnyMediaIdentifier
    ) -> CGFloat? {
        self.mediaViewer(
            mediaViewer,
            widthToHeightOfMediaWith: mediaIdentifier.as(MediaIdentifier.self)
        )
    }
    
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        transitionSourceViewForMediaWith mediaIdentifier: AnyMediaIdentifier
    ) -> UIView? {
        self.mediaViewer(
            mediaViewer,
            transitionSourceViewForMediaWith: mediaIdentifier.as(MediaIdentifier.self)
        )
    }
}
