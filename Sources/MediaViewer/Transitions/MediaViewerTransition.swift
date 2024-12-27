//
//  MediaViewerTransition.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/21.
//

import UIKit

@MainActor
final class MediaViewerTransition: NSObject, UIViewControllerAnimatedTransitioning {
    
    public enum TransitionOperation {
      case present
      case dismiss
    }
    
    private let operation: TransitionOperation
    private let sourceView: UIView?
    private let sourceImage: () -> UIImage?
    
    // MARK: - Initializers
    
    init(
        operation: TransitionOperation,
        sourceView: UIView?,
        sourceImage: @escaping () -> UIImage?
    ) {
        self.operation = operation
        self.sourceView = sourceView
        self.sourceImage = sourceImage
    }
    
    // MARK: - Methods
    
    func transitionDuration(
        using transitionContext: (any UIViewControllerContextTransitioning)?
    ) -> TimeInterval {
        switch operation {
        case .present:
            return 0.3
        case .dismiss:
            return 0.3
        }
    }
    
    func animateTransition(
        using transitionContext: any UIViewControllerContextTransitioning
    ) {
        switch operation {
        case .present:
            animatePushTransition(using: transitionContext)
        case .dismiss:
            animatePopTransition(using: transitionContext)
        }
    }
    
    private func animatePushTransition(
        using transitionContext: some UIViewControllerContextTransitioning
    ) {
        guard let mediaViewer = transitionContext.viewController(forKey: .to) as? MediaViewerViewController,
              let mediaViewerView = transitionContext.view(forKey: .to)
        else {
            preconditionFailure(
                "\(Self.self) works only with the push/pop animation for \(MediaViewerViewController.self)."
            )
        }
        let containerView = transitionContext.containerView
        containerView.addSubview(mediaViewerView)
        
        mediaViewerView.frame = transitionContext.finalFrame(for: mediaViewer)
        
        // Determine the layout of the destination before the transition
        mediaViewerView.layoutIfNeeded()
        
        let currentPageView = mediaViewer.currentPageViewController.mediaViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        
        /*
         NOTE:
         If the image has not yet been fetched asynchronously,
         animate the source image instead.
         */
        if currentPageImageView.image == nil,
           let sourceImage = sourceImage() {
            currentPageView.setImage(sourceImage, with: .none)
        }
        
        let configurationBackup = currentPageImageView.transitioningConfiguration
        let currentPageImageFrameInViewer = mediaViewerView.convert(
            currentPageImageView.frame,
            from: currentPageImageView
        )
        if let sourceView {
            // Match the appearance of the animating image view to the source
            let sourceFrameInViewer = mediaViewerView.convert(
                sourceView.frame,
                from: sourceView.superview
            )
            currentPageView.destroyLayoutConfigurationBeforeTransition()
            currentPageImageView.transitioningConfiguration = sourceView.transitioningConfiguration
            currentPageImageView.frame = sourceFrameInViewer
        } else {
            currentPageView.destroyLayoutConfigurationBeforeTransition()
            currentPageImageView.frame = currentPageImageFrameInViewer
        }
        currentPageImageView.layer.masksToBounds = true
        mediaViewer.insertImageViewForTransition(currentPageImageView)
        sourceView?.isHidden = true
        
        let viewsToFadeInDuringTransition = mediaViewer.subviewsToFadeDuringTransition
        for view in mediaViewer.subviewsToFadeDuringTransition {
            view.alpha = 0
        }
        
        // MARK: Animation
        
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1) {
            for view in viewsToFadeInDuringTransition {
                view.alpha = 1
            }
            currentPageImageView.frame = currentPageImageFrameInViewer
            currentPageImageView.transitioningConfiguration = configurationBackup
            
            // NOTE: Keep following properties during transition for smooth animation.
            if let sourceView = self.sourceView {
                currentPageImageView.contentMode = sourceView.contentMode
            }
            currentPageImageView.layer.masksToBounds = true
        }
        animator.addCompletion { position in
            defer { transitionContext.completeTransition() }
            switch position {
            case .end:
                // Restore properties
                currentPageImageView.transitioningConfiguration = configurationBackup
                currentPageView.restoreLayoutConfigurationAfterTransition()
                self.sourceView?.isHidden = false
            case .start, .current:
                assertionFailure("Unexpected position: \(position)")
            @unknown default:
                assertionFailure("Unknown position: \(position)")
            }
        }
        animator.startAnimation()
    }
    
    private func animatePopTransition(
        using transitionContext: some UIViewControllerContextTransitioning
    ) {
        guard let mediaViewer = transitionContext.viewController(forKey: .from) as? MediaViewerViewController,
              let mediaViewerView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toVC = transitionContext.viewController(forKey: .to)
        else {
            preconditionFailure(
                "\(Self.self) works only with the push/pop animation for \(MediaViewerViewController.self)."
            )
        }
        let containerView = transitionContext.containerView
        containerView.addSubview(toView)
        containerView.addSubview(mediaViewerView)
        
        // MARK: Prepare for the transition
        
        toView.frame = transitionContext.finalFrame(for: toVC)
        toView.layoutIfNeeded()
        
        let currentPageView = mediaViewer.currentPageViewController.mediaViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        let currentPageImageFrameInViewer = mediaViewerView.convert(
            currentPageImageView.frame,
            from: currentPageImageView.superview
        )
        let sourceFrameInViewer = sourceView.map { sourceView in
            mediaViewerView.convert(
                sourceView.frame,
                from: sourceView.superview
            )
        }
        currentPageView.destroyLayoutConfigurationBeforeTransition()
        currentPageImageView.frame = currentPageImageFrameInViewer
        mediaViewer.insertImageViewForTransition(currentPageImageView)
        sourceView?.isHidden = true
        
        let viewsToFadeOutDuringTransition = mediaViewer.subviewsToFadeDuringTransition

        // MARK: Animation
        
        // NOTE: Animate only pageControlToolbar with easeInOut curve.
        UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            mediaViewerView.layoutIfNeeded()
        }.startAnimation()
        
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1) {
            for view in viewsToFadeOutDuringTransition {
                view.alpha = 0
            }
            if let sourceFrameInViewer {
                currentPageImageView.frame = sourceFrameInViewer
                currentPageImageView.transitioningConfiguration = self.sourceView!.transitioningConfiguration
            } else {
                currentPageImageView.alpha = 0
            }
            currentPageImageView.clipsToBounds = true // TODO: Change according to the source configuration
        }
        
        animator.addCompletion { position in
            defer { transitionContext.completeTransition() }
            switch position {
            case .end:
                mediaViewerView.removeFromSuperview()
                
                // Restore properties
                self.sourceView?.isHidden = false
            case .start, .current:
                assertionFailure("Unexpected position: \(position)")
            @unknown default:
                assertionFailure("Unknown position: \(position)")
            }
        }
        animator.startAnimation()
    }
}
