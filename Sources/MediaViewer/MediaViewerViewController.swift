//
//  MediaViewerViewController.swift
//
//
//  Created by Yusaku Nishi on 2023/02/25.
//

import UIKit
import Combine

/// An media viewer.
///
/// It is recommended to set your `MediaViewerViewController` instance to
/// `navigationController?.delegate` to enable smooth transition animation.
///
/// ```swift
/// let mediaViewer = MediaViewerViewController(opening: 0, dataSource: self)
/// navigationController?.delegate = mediaViewer
/// navigationController?.pushViewController(mediaViewer, animated: true)
/// ```
///
/// To show toolbar items in the media viewer, use `toolbarItems` property on the viewer instance.
///
/// ```swift
/// mediaViewer.toolbarItems = [
///     UIBarButtonItem(...)
/// ]
/// ```
///
/// You can subclass `MediaViewerViewController` and customize it.
///
/// - Note: `MediaViewerViewController` must be embedded in
///         `UINavigationController`.
/// - Note: It is NOT allowed to change `dataSource` and `delegate` properties
///         of ``UIPageViewController``.
open class MediaViewerViewController: UIPageViewController {
    
    private var cancellables: Set<AnyCancellable> = []
    
    /// The data source of the media viewer object.
    ///
    /// - Note: This data source object must be set at object creation time and may not be changed.
    open private(set) weak var mediaViewerDataSource: (any MediaViewerDataSource)!
    
    /// The object that acts as the delegate of the media viewer.
    ///
    /// - Precondition: The associated type `MediaIdentifier` must be the same as
    ///                 the one of `mediaViewerDataSource`.
    open weak var mediaViewerDelegate: (any MediaViewerDelegate)? {
        willSet {
            guard let mediaViewerDataSource else { return }
            newValue?.verifyMediaIdentifierTypeIsSame(as: mediaViewerDataSource)
        }
    }
    
    /// The current page of the media viewer.
    @available(*, deprecated)
    public var currentPage: Int {
        mediaViewerVM.page(with: currentMediaIdentifier)!
    }
    
    /// Returns the identifier for currently viewing media in the viewer.
    /// - Parameter identifierType: A type of the identifier for media.
    ///                             It must match the one provided by `mediaViewerDataSource`.
    public func currentMediaIdentifier<MediaIdentifier>(
        as identifierType: MediaIdentifier.Type = MediaIdentifier.self
    ) -> MediaIdentifier {
        currentMediaIdentifier.as(MediaIdentifier.self)
    }
    
    var currentMediaIdentifier: AnyMediaIdentifier {
        visiblePageViewController.mediaIdentifier
    }
    
    var pendingMediaIdentifier: AnyMediaIdentifier? {
        pageTransitionState.pendingViewController?.mediaIdentifier
    }
    
    public func pendingMediaIdentifier<MediaIdentifier>(
        as identifierType: MediaIdentifier.Type = MediaIdentifier.self
    ) -> MediaIdentifier? {
        pendingMediaIdentifier?.as(MediaIdentifier.self)
    }
    
    /// A view controller for the currently visible page.
    var visiblePageViewController: MediaViewerOnePageViewController {
        guard let mediaViewerOnePage = viewControllers?.first as? MediaViewerOnePageViewController else {
            preconditionFailure(
                "\(Self.self) must have only one \(MediaViewerOnePageViewController.self)."
            )
        }
        return mediaViewerOnePage
    }
    
    private var destinationPageVCAfterReloading: MediaViewerOnePageViewController?
    
    private let mediaViewerVM = MediaViewerViewModel()
    
    private lazy var scrollView = view.firstSubview(ofType: UIScrollView.self)!
    
    private let panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }()
    
    private var interactivePopTransition: MediaViewerInteractivePopTransition?
    
    public var navController: UINavigationController? {
        presentationController?.presentingViewController as? UINavigationController
    }
    
    // MARK: Backups
     
    private(set) var tabBarAlphaBackup: CGFloat?
    private(set) var navigationBarAlphaBackup: CGFloat?
    
    private var pageTransitionState: PageTransitionState = .init()

    private struct PageTransitionState {
        var pendingViewController: MediaViewerOnePageViewController?
        var titleState: TitleState = .current

        var isTransitioning: Bool {
            pendingViewController != nil
        }

        mutating func reset() {
            pendingViewController = nil
            titleState = .current
        }

        enum TitleState {
            case next
            case current
        }
    }

    // MARK: - Initializers
    
    /// Creates a new viewer.
    /// - Parameters:
    ///   - mediaIdentifier: An identifier for media to view first.
    ///   - dataSource: The data source for the viewer.
    public init<MediaIdentifier>(
        opening mediaIdentifier: MediaIdentifier,
        dataSource: some MediaViewerDataSource<MediaIdentifier>
    ) {
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [
                .interPageSpacing: 40,
                .spineLocation: SpineLocation.none.rawValue
            ]
        )
        mediaViewerDataSource = dataSource
        
        let identifiers = dataSource.mediaIdentifiers(for: self)
        precondition(
            identifiers.contains(mediaIdentifier),
            "mediaIdentifier \(mediaIdentifier) must be included in identifiers returned by dataSource.mediaIdentifiers(for:)."
        )
        
        mediaViewerVM.mediaIdentifiers = identifiers.map(AnyMediaIdentifier.init)
        
        let mediaViewerPage = makeMediaViewerPage(
            with: AnyMediaIdentifier(mediaIdentifier)
        )
        setViewControllers([mediaViewerPage], direction: .forward, animated: false)
        
        hidesBottomBarWhenPushed = true
    }
    
    @available(*, unavailable, message: "init(coder:) is not supported.")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    open override func loadView() {
        super.loadView()
        
        dataSource = self
        delegate = self
        scrollView.delegate = self

        guard let navigationController = navController else {
            preconditionFailure(
                "\(Self.self) must be embedded in UINavigationController."
            )
        }
        
        let tabBar = navigationController.tabBarController?.tabBar
        tabBarAlphaBackup = tabBar?.alpha
        navigationBarAlphaBackup = navigationController.navigationBar.alpha
        
        setUpGestureRecognizers()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        /*
         NOTE:
         This delegate method is also called at initialization time,
         but since the delegate has not yet been set by the caller,
         it needs to be told to the caller again at this time.
         */
        mediaViewerDelegate?.mediaViewer(
            self,
            didMoveToMediaWith: currentMediaIdentifier
        )
    }
    
    private func setUpGestureRecognizers() {
        panRecognizer.delegate = self
        panRecognizer.addTarget(self, action: #selector(panned))
        view.addGestureRecognizer(panRecognizer)
    }
    
    // MARK: - Override
    
    open override func setViewControllers(
        _ viewControllers: [UIViewController]?,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        super.setViewControllers(
            viewControllers,
            direction: direction,
            animated: animated,
            completion: completion
        )
        pageDidChange()
    }
    
    // MARK: - Methods
    
    /// Fetches type-erased identifiers for media from the data source.
    func fetchMediaIdentifiers() -> [AnyMediaIdentifier] {
        mediaViewerDataSource
            .mediaIdentifiers(for: self)
            .map { AnyMediaIdentifier($0) }
    }
    
    /// Move to media with the specified identifier.
    /// - Parameters:
    ///   - identifier: An identifier for destination media.
    ///   - animated: A Boolean value that indicates whether the transition is to be animated.
    ///   - completion: A closure to be called when the animation completes.
    ///                 It takes a boolean value whether the transition is finished or not.
    open func move<MediaIdentifier>(
        toMediaWith identifier: MediaIdentifier,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) where MediaIdentifier: Hashable {
        let identifier = AnyMediaIdentifier(identifier)
        move(
            to: makeMediaViewerPage(with: identifier),
            direction: mediaViewerVM.moveDirection(
                from: currentMediaIdentifier,
                to: identifier
            ),
            animated: animated,
            completion: completion
        )
    }
    
    private func move(
        to mediaViewerPage: MediaViewerOnePageViewController,
        direction: NavigationDirection,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        setViewControllers(
            [mediaViewerPage],
            direction: direction,
            animated: animated,
            completion: completion
        )
    }
    
    private func pageDidChange() {
        mediaViewerDelegate?.mediaViewer(
            self,
            didMoveToMediaWith: currentMediaIdentifier
        )
    }
    
    private func pageIsTransitioning() {
        let transitioningMediaIdentifier =
        switch pageTransitionState.titleState {
            case .next:
                pageTransitionState.pendingViewController?.mediaIdentifier ?? currentMediaIdentifier
            case .current:
                currentMediaIdentifier
            }
        mediaViewerDelegate?.mediaViewerPageIsTransitioning(
            self,
            transitioningMedia: transitioningMediaIdentifier
        )
    }
    
    // MARK: - Actions

    @objc
    private func panned(recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began {
            // Start the interactive pop transition
            let sourceView = mediaViewerDataSource.mediaViewer(
                self,
                transitionSourceViewForMediaWith: currentMediaIdentifier
            )
            interactivePopTransition = .init(
              sourceView: sourceView
            )

            /*
             [Workaround]
             If the recognizer detects a gesture while the main thread is blocked,
             the interactive transition will not work properly.
             By delaying popViewController with Task, recognizer.state becomes
             `.ended` first and interactivePopTransition becomes nil,
             so a normal transition runs and avoids that problem.
             
             However, it leads to another glitch:
             later interactivePopTransition.panRecognized(by:in:) changes
             the anchor point of the image view while it is still on the
             scroll view, causing the image view to be shifted.
             To avoid it, call prepareForInteractiveTransition(for:) and
             remove the image view from the scroll view in advance.
             */
            interactivePopTransition?.prepareForInteractiveTransition(for: self)
            Task {
                self.dismiss(animated: true)
            }
        }
        
        interactivePopTransition?.panRecognized(by: recognizer, in: self)
        
        switch recognizer.state {
        case .possible, .began, .changed:
            break
        case .ended, .cancelled, .failed:
            interactivePopTransition = nil
        @unknown default:
            assertionFailure("Unknown state: \(recognizer.state)")
            interactivePopTransition = nil
        }
    }
}

// MARK: - MediaViewerOnePageViewControllerDelegate -

extension MediaViewerViewController: MediaViewerOnePageViewControllerDelegate {
    
    func mediaViewerPageTapped(
        _ mediaViewerPage: MediaViewerOnePageViewController
    ) {
        mediaViewerDelegate?.mediaViewerPageTapped(self)
    }
    
    func mediaViewerPageDidZoom(
        _ mediaViewerPage: MediaViewerOnePageViewController
    ) {
        guard mediaViewerPage == visiblePageViewController else {
            // NOTE: Comes here when the delete animation is complete.
            return
        }
        let isAtMinimumScale =
            mediaViewerPage.mediaViewerOnePageView.scrollView.zoomScale == mediaViewerPage.mediaViewerOnePageView.scrollView.minimumZoomScale
        mediaViewerDelegate?.mediaViewerPageDidZoom(self, isAtMinimumScale: isAtMinimumScale)
    }

    func mediaViewerPageWillBeginDragging(_ mediaViewerPage: MediaViewerOnePageViewController) {
        mediaViewerDelegate?.mediaViewerPageWillBeginDragging(self)
    }
}

// MARK: - UIPageViewControllerDataSource -

extension MediaViewerViewController: UIPageViewControllerDataSource {
    
    open func presentationCount(for pageViewController: UIPageViewController) -> Int {
        mediaViewerVM.mediaIdentifiers.count
    }
    
    open func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let mediaViewerPageVC = viewController as? MediaViewerOnePageViewController else {
            assertionFailure("Unknown view controller: \(viewController)")
            return nil
        }
        guard let previousIdentifier = mediaViewerVM.mediaIdentifier(before: mediaViewerPageVC.mediaIdentifier) else {
            return nil
        }
        return makeMediaViewerPage(with: previousIdentifier)
    }
    
    open func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let mediaViewerPageVC = viewController as? MediaViewerOnePageViewController else {
            assertionFailure("Unknown view controller: \(viewController)")
            return nil
        }
        guard let nextIdentifier = mediaViewerVM.mediaIdentifier(after: mediaViewerPageVC.mediaIdentifier) else {
            return nil
        }
        return makeMediaViewerPage(with: nextIdentifier)
    }
    
    private func makeMediaViewerPage(
        with identifier: AnyMediaIdentifier
    ) -> MediaViewerOnePageViewController {
        let mediaViewerPage = MediaViewerOnePageViewController(
            mediaIdentifier: identifier
        )
        mediaViewerPage.delegate = self
        
        let media = mediaViewerDataSource.mediaViewer(self, mediaWith: identifier)
        switch media {
        case .image(.sync(let image)):
            mediaViewerPage.mediaViewerOnePageView.setImage(image, with: .none)
        case .image(.async(let transition, let imageProvider)):
            Task(priority: .high) {
                let image = await imageProvider()
                mediaViewerPage.mediaViewerOnePageView.setImage(image, with: transition)
            }
        }
        return mediaViewerPage
    }
}

// MARK: - UIPageViewControllerDelegate -

extension MediaViewerViewController: UIPageViewControllerDelegate {
    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let firstPendingViewController = pendingViewControllers.first else {
            return
        }

        guard let mediaViewerOnePage = firstPendingViewController as? MediaViewerOnePageViewController else {
            preconditionFailure(
              "All ViewControllers in \(Self.self) must be of type \(MediaViewerOnePageViewController.self)."
            )
        }

        pageTransitionState.pendingViewController = mediaViewerOnePage
  }

    open func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        if completed {
            pageTransitionState.reset()

            pageDidChange()
        }
    }
}

// MARK: - UIViewControllerTransitioningDelegate -

extension MediaViewerViewController: UIViewControllerTransitioningDelegate {

    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        let sourceView = mediaViewerDataSource.mediaViewer(
            self,
            transitionSourceViewForMediaWith: currentMediaIdentifier
        )

        return MediaViewerTransition(
            operation: .present,
            sourceView: sourceView,
            sourceImage: { [weak self] in
                guard let self else { return nil }
                return mediaViewerDataSource.mediaViewer(
                    self,
                    transitionSourceImageWith: sourceView
                )
            }
        )
    }

    public func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        // Handle dismissal animation
        if mediaViewerDataSource.mediaIdentifiers(for: self).isEmpty {
            // When all media is deleted
            return MediaViewerTransition(
                operation: .dismiss,
                sourceView: nil,
                sourceImage: { nil }
            )
        }
        
        let sourceView = interactivePopTransition?.sourceView ?? mediaViewerDataSource.mediaViewer(
            self,
            transitionSourceViewForMediaWith: currentMediaIdentifier
        )

        mediaViewerDelegate?.mediaViewer(
            self,
            willBeginPopTransitionTo: presentingViewController ?? UIViewController()
        )

        return MediaViewerTransition(
            operation: .dismiss,
            sourceView: sourceView,
            sourceImage: { [weak self] in
                guard let self else { return nil }
                return mediaViewerDataSource.mediaViewer(
                    self,
                    transitionSourceImageWith: sourceView
                )
            }
        )
    }
    
    public func interactionControllerForDismissal(
        using animator: any UIViewControllerAnimatedTransitioning
    ) -> (any UIViewControllerInteractiveTransitioning)? {
        interactivePopTransition
    }
}

// MARK: - UIGestureRecognizerDelegate -

extension MediaViewerViewController: UIGestureRecognizerDelegate {
    
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Tune gesture recognizers to make it easier to start an interactive pop.
        guard gestureRecognizer == panRecognizer else { return false }
        let velocity = panRecognizer.velocity(in: nil)
        let isMovingDown = velocity.y > 0 && velocity.y > abs(velocity.x)
        
        let mediaScrollView = visiblePageViewController.mediaViewerOnePageView.scrollView
        switch otherGestureRecognizer {
        case mediaScrollView.panGestureRecognizer:
            // If the scroll position reaches the top edge, allow an interactive pop by pulldown.
            let isReachingTopEdge = mediaScrollView.contentOffset.y <= 0
            if isReachingTopEdge && isMovingDown {
                // Make scrolling fail
                mediaScrollView.panGestureRecognizer.state = .failed
                return true
            }
        case let pagingRecognizer as UIPanGestureRecognizer
            where pagingRecognizer.view is UIScrollView:
            switch pagingRecognizer.view?.superview {
            case view:
                // Prefer an interactive pop over paging.
                if isMovingDown {
                    // Make paging fail
                    pagingRecognizer.state = .failed
                    return true
                }
            default:
                assertionFailure(
                    "Unknown pan gesture recognizer: \(otherGestureRecognizer)"
                )
            }
        default:
            break
        }
        return false
    }
}

// MARK: - UIScrollViewDelegate -

extension MediaViewerViewController: UIScrollViewDelegate {
  public func scrollViewDidScroll(_ scrollView: UIScrollView) {
      guard pageTransitionState.isTransitioning else { return }

      let pageWidth = scrollView.bounds.width
      let offset = scrollView.contentOffset.x
      let progress = (offset - pageWidth) / pageWidth

      // Only allow title updates if we have a valid pending VC and the scroll
      // is moving in the correct direction for that pending VC
      guard let pendingVC = pageTransitionState.pendingViewController else {
          pageTransitionState.titleState = .current
          pageIsTransitioning()
          return
      }

      // Determine if we're moving forward or backward based on pending VC
      let isPendingForward = mediaViewerVM.page(with: pendingVC.mediaIdentifier)! >
                            mediaViewerVM.page(with: currentMediaIdentifier)!

      // Only update direction if scroll direction matches pending direction
      if (isPendingForward && progress > 0) || (!isPendingForward && progress < 0) {
          let newTitleState: PageTransitionState.TitleState = if abs(progress) > 0.5 {
              .next
          } else {
              .current
          }

          if newTitleState != pageTransitionState.titleState {
              pageTransitionState.titleState = newTitleState
              pageIsTransitioning()
          }
      } else {
          pageTransitionState.titleState = .current
          pageIsTransitioning()
      }
  }
}

// MARK: - Transition helpers -

extension MediaViewerViewController {
    
    var subviewsToFadeDuringTransition: [UIView] {
        view.subviews
            .filter {
                $0 != visiblePageViewController.mediaViewerOnePageView.imageView
            }
    }
    
    /// Insert an animated image view for the transition.
    /// - Parameter animatedImageView: An animated image view during the transition.
    func insertImageViewForTransition(_ animatedImageView: UIImageView) {
      view.addSubview(animatedImageView)
    }
}
