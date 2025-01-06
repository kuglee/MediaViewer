//
//  MediaViewerInteractivePopTransition.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/23.
//

import UIKit

@MainActor
final class MediaViewerInteractivePopTransition: NSObject {
    
    let sourceView: UIView?
    
    private var animator: UIViewPropertyAnimator?
    private var transitionContext: (any UIViewControllerContextTransitioning)?
    private var tabBarSnapshot: UIView?
    private var navigationBarSnapshot: UIView?
    
    // MARK: Backups
    
    private var sourceViewHiddenBackup = false
    private var initialZoomScale: CGFloat = 1
    private var initialImageTransform = CGAffineTransform.identity
    private var initialImageFrameInViewer = CGRect.null

    private var didPrepare = false
    
    // MARK: - Initializers
    
    init(sourceView: UIView?) {
        self.sourceView = sourceView
        super.init()
    }
}

extension MediaViewerInteractivePopTransition: UIViewControllerInteractiveTransitioning {
    
    func prepareForInteractiveTransition(
        for mediaViewer: MediaViewerViewController
    ) {
        assert(!didPrepare)
        defer { didPrepare = true }
        
        let mediaViewerView = mediaViewer.view!
        let currentPageView = mediaViewer.visiblePageViewController.mediaViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        
        // Backup
        initialZoomScale = currentPageView.scrollView.zoomScale
        initialImageTransform = currentPageImageView.transform
        initialImageFrameInViewer = mediaViewerView.convert(
            currentPageImageView.frame,
            from: currentPageImageView.superview
        )
        
        // MARK: Prepare for the transition
        
        /*
         NOTE:
         The main purpose of prepareForInteractiveTransition(for:) is
         to destroy the layout.
         For more information, check the caller.
         */
        currentPageView.destroyLayoutConfigurationBeforeTransition()
        currentPageImageView.frame = initialImageFrameInViewer
        mediaViewer.insertImageViewForTransition(currentPageImageView)
    }
    
    func startInteractiveTransition(
        _ transitionContext: any UIViewControllerContextTransitioning
    ) {
        assert(didPrepare)
        
        guard let mediaViewer = transitionContext.viewController(forKey: .from) as? MediaViewerViewController
        else {
            preconditionFailure(
                "\(Self.self) works only with the pop animation for \(MediaViewerViewController.self)."
            )
        }
        self.transitionContext = transitionContext
        let containerView = transitionContext.containerView
        containerView.addSubview(mediaViewer.view)
        
        // Back up
        sourceViewHiddenBackup = sourceView?.isHidden ?? false
        
        // MARK: Prepare for the transition
        
        sourceView?.isHidden = true
        
        let navigationController = mediaViewer.parentNavigationController
        
        tabBarSnapshot = navigationController?.tabBarController?.tabBar.snapshotViewWithFrame(
            afterScreenUpdates: true
        )
        if let tabBarSnapshot {
            tabBarSnapshot.alpha = 0
            containerView.addSubview(tabBarSnapshot)
        }
        
        navigationBarSnapshot = navigationController?.navigationBar.snapshotViewWithSafeArea(
            afterScreenUpdates: true
        )
        if let navigationBarSnapshot {
            navigationBarSnapshot.alpha = 0
            containerView.addSubview(navigationBarSnapshot)
        }
        
        let viewsToFadeOutDuringTransition = mediaViewer.subviewsToFadeDuringTransition
        
        // MARK: Animation
        
        animator = UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) {
            if let tabBarSnapshot = self.tabBarSnapshot,
                let tabBarAlphaBackup = mediaViewer.tabBarAlphaBackup,
                tabBarAlphaBackup != 0 {
                tabBarSnapshot.alpha = tabBarAlphaBackup
            }

            if let navigationBarSnapshot = self.navigationBarSnapshot,
                let navigationBarAlphaBackup = mediaViewer.navigationBarAlphaBackup,
                navigationBarAlphaBackup != 0 {
                navigationBarSnapshot.alpha = navigationBarAlphaBackup
            }

            for view in viewsToFadeOutDuringTransition {
                view.alpha = 0
            }
        }
    }
    
    private func finishInteractiveTransition() {
        guard let animator, let transitionContext else { return }
        transitionContext.finishInteractiveTransition()
        
        animator.continueAnimation(withTimingParameters: nil, durationFactor: 1)
        
        let mediaViewerView = transitionContext.view(forKey: .from)!
        let currentPageView = mediaViewerCurrentPageView(in: transitionContext)
        let currentPageImageView = currentPageView.imageView
        
        let finishAnimator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 1) {
            if let sourceView = self.sourceView {
                let sourceFrameInViewer = mediaViewerView.convert(
                    sourceView.frame,
                    from: sourceView.superview
                )
                currentPageImageView.frame = sourceFrameInViewer
                currentPageImageView.transitioningConfiguration = sourceView.transitioningConfiguration
                currentPageImageView.layer.masksToBounds = true // TODO: Change according to the source configuration
            } else {
                currentPageImageView.alpha = 0
            }
        }

        finishAnimator.addCompletion { _ in
            mediaViewerView.removeFromSuperview()
            
            // Restore properties
            self.sourceView?.isHidden = self.sourceViewHiddenBackup

            transitionContext.completeTransition(true)
        }
        finishAnimator.startAnimation()
    }
    
    private func cancelInteractiveTransition() {
        guard let animator, let transitionContext else { return }
        transitionContext.cancelInteractiveTransition()
        
        animator.isReversed = true
        animator.continueAnimation(withTimingParameters: nil, durationFactor: 1)
        
        let currentPageView = mediaViewerCurrentPageView(in: transitionContext)
        let currentPageImageView = currentPageView.imageView

        let cancelAnimator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) {
            currentPageImageView.frame = self.initialImageFrameInViewer
        }
        
        cancelAnimator.addCompletion { _ in
            // Restore to pre-transition state
            self.sourceView?.isHidden = self.sourceViewHiddenBackup
            currentPageImageView.updateAnchorPointWithoutMoving(.init(x: 0.5, y: 0.5))
            currentPageImageView.transform = self.initialImageTransform
            currentPageView.restoreLayoutConfigurationAfterTransition()
            
            transitionContext.completeTransition(false)
        }
        cancelAnimator.startAnimation()
    }
    
    private func mediaViewerCurrentPageView(
        in transitionContext: some UIViewControllerContextTransitioning
    ) -> MediaViewerOnePageView {
        guard let mediaViewer = transitionContext.viewController(forKey: .from) as? MediaViewerViewController else {
            preconditionFailure(
                "\(Self.self) works only with the pop animation for \(MediaViewerViewController.self)."
            )
        }
        return mediaViewer.visiblePageViewController.mediaViewerOnePageView
    }
    
    func panRecognized(
        by recognizer: UIPanGestureRecognizer,
        in mediaViewer: MediaViewerViewController
    ) {
        let currentPageView = mediaViewer.visiblePageViewController.mediaViewerOnePageView
        let panningImageView = currentPageView.imageView
        
        switch recognizer.state {
        case .possible, .began:
            // Adjust the anchor point to scale the image around a finger
            let location = recognizer.location(in: currentPageView.scrollView)
            let anchorPoint = CGPoint(
                x: location.x / panningImageView.frame.width,
                y: location.y / panningImageView.frame.height
            )
            panningImageView.updateAnchorPointWithoutMoving(anchorPoint)
        case .changed:
            guard let animator, let transitionContext else {
                // NOTE: Sometimes this method is called before startInteractiveTransition(_:) and enters here.
                return
            }
            let translation = recognizer.translation(in: currentPageView)
            let panAreaSize = currentPageView.bounds.size
            
            let transitionProgress = translation.y * 2 / panAreaSize.height
            let fractionComplete = max(min(transitionProgress, 1), 0)
            animator.fractionComplete = fractionComplete
            transitionContext.updateInteractiveTransition(fractionComplete)
            
            panningImageView.transform = panningImageTransform(
                translation: translation,
                panAreaSize: panAreaSize
            )
        case .ended:
            let isMovingDown = recognizer.velocity(in: nil).y > 0
            if isMovingDown {
                finishInteractiveTransition()
            } else {
                cancelInteractiveTransition()
            }
        case .cancelled, .failed:
            cancelInteractiveTransition()
        @unknown default:
            assertionFailure()
            cancelInteractiveTransition()
        }
    }
    
    /// Calculate an affine transformation matrix for the panning image.
    ///
    /// Ease translation and image scale changes.
    ///
    /// - Parameters:
    ///   - translation: The total translation over time.
    ///   - panAreaSize: The size of the panning area.
    /// - Returns: An affine transformation matrix for the panning image.
    private func panningImageTransform(
        translation: CGPoint,
        panAreaSize: CGSize
    ) -> CGAffineTransform {
        // Translation x: ease-in-out from the left to the right
        let maxX = panAreaSize.width * 0.4
        let translationX = sin(translation.x / panAreaSize.width * .pi / 2) * maxX
        
        let translationY: CGFloat
        let imageScale: CGFloat
        if translation.y >= 0 {
            // Translation y: linear during pull-down
            translationY = translation.y
            
            // Image scale: ease-out during pull-down
            let maxScale = 1.0
            let minScale = 0.6
            let difference = maxScale - minScale
            imageScale = maxScale - sin(translation.y * .pi / 2 / panAreaSize.height) * difference
        } else {
            // Translation y: ease-out during pull-up
            let minY = -panAreaSize.height / 3.8
            translationY = easeOutQuadratic(-translation.y / panAreaSize.height) * minY
            
            // Image scale: not change during pull-up
            imageScale = 1
        }
        return initialImageTransform
            .translatedBy(
                x: translationX / initialZoomScale,
                y: translationY / initialZoomScale
            )
            .scaledBy(x: imageScale, y: imageScale)
    }
    
    private func easeOutQuadratic(_ x: Double) -> Double {
        -x * (x - 2)
    }
}
