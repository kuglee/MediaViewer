//
//  MediaViewerTransition.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/21.
//

import UIKit

@MainActor
final class MediaViewerTransition: NSObject, UIViewControllerAnimatedTransitioning {
    
    let operation: UINavigationController.Operation
    let sourceImageView: UIImageView?
    
    // MARK: - Initializers
    
    init(
        operation: UINavigationController.Operation,
        sourceImageView: UIImageView?
    ) {
        self.operation = operation
        self.sourceImageView = sourceImageView
    }
    
    // MARK: - Methods
    
    func transitionDuration(
        using transitionContext: (any UIViewControllerContextTransitioning)?
    ) -> TimeInterval {
        switch operation {
        case .push:
            return 0.5
        case .pop:
            return 0.35
        case .none:
            return 0.3
        @unknown default:
            return 0.3
        }
    }
    
    func animateTransition(
        using transitionContext: any UIViewControllerContextTransitioning
    ) {
        switch operation {
        case .push:
            animatePushTransition(using: transitionContext)
        case .pop:
            animatePopTransition(using: transitionContext)
        case .none:
            fatalError("Not implemented.")
        @unknown default:
            fatalError("Not implemented.")
        }
    }
    
    private func animatePushTransition(
        using transitionContext: some UIViewControllerContextTransitioning
    ) {
        guard let mediaViewer = transitionContext.viewController(forKey: .to) as? MediaViewerViewController,
              let mediaViewerView = transitionContext.view(forKey: .to),
              let navigationController = mediaViewer.navigationController
        else {
            preconditionFailure(
                "\(Self.self) works only with the push/pop animation for \(MediaViewerViewController.self)."
            )
        }
        let containerView = transitionContext.containerView
        containerView.addSubview(mediaViewerView)
        
        let tabBar = mediaViewer.tabBarController?.tabBar
        
        // Back up
        let sourceImageHiddenBackup = sourceImageView?.isHidden ?? false
        let tabBarSuperviewBackup = tabBar?.superview
        let tabBarHiddenBackup = tabBar?.isHidden
        let tabBarScrollEdgeAppearanceBackup = tabBar?.scrollEdgeAppearance
        
        // MARK: Prepare for the transition
        
        mediaViewerView.frame = transitionContext.finalFrame(for: mediaViewer)
        
        // Determine the layout of the destination before the transition
        mediaViewerView.layoutIfNeeded()
        
        let currentPageView = mediaViewer.currentPageViewController.mediaViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        
        /*
         * NOTE:
         * If the image has not yet been fetched asynchronously,
         * animate the source image instead.
         */
        if currentPageImageView.image == nil, let sourceImageView {
            currentPageView.setImage(sourceImageView.image, with: .none)
        }
        
        let configurationBackup = currentPageImageView.transitioningConfiguration
        let currentPageImageFrameInViewer = mediaViewerView.convert(
            currentPageImageView.frame,
            from: currentPageImageView
        )
        if let sourceImageView {
            // Match the appearance of the animating image view to the source
            let sourceImageFrameInViewer = mediaViewerView.convert(
                sourceImageView.frame,
                from: sourceImageView
            )
            currentPageView.destroyLayoutConfigurationBeforeTransition()
            currentPageImageView.transitioningConfiguration = sourceImageView.transitioningConfiguration
            currentPageImageView.frame = sourceImageFrameInViewer
        } else {
            currentPageView.destroyLayoutConfigurationBeforeTransition()
            currentPageImageView.frame = currentPageImageFrameInViewer
        }
        currentPageImageView.layer.masksToBounds = true
        mediaViewer.insertImageViewForTransition(currentPageImageView)
        sourceImageView?.isHidden = true
        
        if let tabBar {
            // Show the tabBar during the transition
            containerView.addSubview(tabBar)
            tabBar.isHidden = false
            
            // Make the tabBar opaque during the transition
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            tabBar.scrollEdgeAppearance = appearance
            
            // Disable the default animation applied to the tabBar
            if mediaViewer.hidesBottomBarWhenPushed,
               let animationKeys = tabBar.layer.animationKeys() {
                assert(animationKeys.allSatisfy { $0.starts(with: "position") })
                tabBar.layer.removeAllAnimations()
            }
        }
        
        // Disable the default animation applied to the toolbar
        let toolbar = navigationController.toolbar!
        if let animationKeys = toolbar.layer.animationKeys() {
            assert(animationKeys.allSatisfy { $0.starts(with: "position") })
            toolbar.layer.removeAllAnimations()
        }
        
        toolbar.alpha = 0
        let viewsToFadeDuringTransition = mediaViewer.subviewsToFadeDuringTransition
        for view in viewsToFadeDuringTransition {
            view.alpha = 0
        }
        
        mediaViewer.willStartPushTransition()
        
        // MARK: Animation
        
        // NOTE: Animate only pageControlToolbar with easeInOut curve.
        UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            mediaViewerView.layoutIfNeeded()
        }.startAnimation()
        
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 0.7) {
            toolbar.alpha = 1
            for view in viewsToFadeDuringTransition {
                view.alpha = 1
            }
            currentPageImageView.frame = currentPageImageFrameInViewer
            currentPageImageView.transitioningConfiguration = configurationBackup
            
            // NOTE: Keep following properties during transition for smooth animation.
            if let sourceImageView = self.sourceImageView {
                currentPageImageView.contentMode = sourceImageView.contentMode
            }
            currentPageImageView.layer.masksToBounds = true
        }
        animator.addCompletion { position in
            defer { transitionContext.completeTransition() }
            switch position {
            case .end:
                // Restore properties
                mediaViewer.didFinishPushTransition()
                currentPageImageView.transitioningConfiguration = configurationBackup
                currentPageView.restoreLayoutConfigurationAfterTransition()
                self.sourceImageView?.isHidden = sourceImageHiddenBackup
                
                if let tabBar {
                    tabBar.isHidden = tabBarHiddenBackup!
                    tabBar.scrollEdgeAppearance = tabBarScrollEdgeAppearanceBackup
                    tabBarSuperviewBackup?.addSubview(tabBar)
                }
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
              let toVC = transitionContext.viewController(forKey: .to),
              let navigationController = mediaViewer.navigationController
        else {
            preconditionFailure(
                "\(Self.self) works only with the push/pop animation for \(MediaViewerViewController.self)."
            )
        }
        let containerView = transitionContext.containerView
        containerView.addSubview(toView)
        containerView.addSubview(mediaViewerView)
        
        // Back up
        let sourceImageHiddenBackup = sourceImageView?.isHidden ?? false
        
        // MARK: Prepare for the transition
        
        toView.frame = transitionContext.finalFrame(for: toVC)
        toView.layoutIfNeeded()
        
        let currentPageView = mediaViewer.currentPageViewController.mediaViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        let currentPageImageFrameInViewer = mediaViewerView.convert(
            currentPageImageView.frame,
            from: currentPageView.scrollView
        )
        let sourceImageFrameInViewer = sourceImageView.map { sourceView in
            mediaViewerView.convert(sourceView.frame, from: sourceView)
        }
        currentPageView.destroyLayoutConfigurationBeforeTransition()
        currentPageImageView.frame = currentPageImageFrameInViewer
        mediaViewer.insertImageViewForTransition(currentPageImageView)
        sourceImageView?.isHidden = true
        
        let toolbar = navigationController.toolbar!
        assert(toolbar.layer.animationKeys() == nil)
        
        mediaViewer.willStartPopTransition()
        
        // MARK: Animation
        
        // NOTE: Animate only pageControlToolbar with easeInOut curve.
        UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            mediaViewerView.layoutIfNeeded()
        }.startAnimation()
        
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1) {
            for subview in mediaViewer.subviewsToFadeDuringTransition {
                subview.alpha = 0
            }
            if let sourceImageFrameInViewer {
                currentPageImageView.frame = sourceImageFrameInViewer
                currentPageImageView.transitioningConfiguration = self.sourceImageView!.transitioningConfiguration
            } else {
                currentPageImageView.alpha = 0
            }
            currentPageImageView.clipsToBounds = true // TODO: Change according to the source configuration
        }
        
        // Customize the tabBar animation
        if let tabBar = toVC.tabBarController?.tabBar,
           let animationKeys = tabBar.layer.animationKeys() {
            assert(animationKeys.allSatisfy { $0.starts(with: "position") })
            tabBar.layer.removeAllAnimations()
            
            if toVC.hidesBottomBarWhenPushed {
                // Fade out the tabBar
                animator.addAnimations {
                    tabBar.alpha = 0
                }
                animator.addCompletion { position in
                    if position == .end {
                        tabBar.alpha = 1 // Reset
                    }
                }
            } else {
                // Fade in the tabBar
                tabBar.alpha = 0
                animator.addAnimations {
                    tabBar.alpha = 1
                }
            }
        }
        
        animator.addCompletion { position in
            defer { transitionContext.completeTransition() }
            switch position {
            case .end:
                mediaViewerView.removeFromSuperview()
                
                // Restore properties
                self.sourceImageView?.isHidden = sourceImageHiddenBackup
                navigationController.isToolbarHidden = mediaViewer.toolbarHiddenBackup
                
                // Disable the default animation applied to the toolbar
                if let animationKeys = toolbar.layer.animationKeys() {
                    assert(animationKeys.allSatisfy {
                        $0.starts(with: "position")
                        || $0.starts(with: "bounds.size")
                    })
                    toolbar.layer.removeAllAnimations()
                }
            case .start, .current:
                assertionFailure("Unexpected position: \(position)")
            @unknown default:
                assertionFailure("Unknown position: \(position)")
            }
        }
        animator.startAnimation()
    }
}