import MediaViewer
import Nuke
import UIKit

final class NukeImagesViewController: UIViewController {
  let remoteImages: [RemoteImage]
  weak var mediaViewer: CustomMediaViewerViewController?

  private typealias CellRegistration = UICollectionView.CellRegistration<
    ImageCell,
    (
      asset: RemoteImage, contentMode: UIView.ContentMode, screenScale: CGFloat, index: Int,
      callback: (CGFloat) -> Void
    )
  >

  private let imageGridView = ImageGridView()

  private let cellRegistration = CellRegistration { cell, _, item in
    cell.configure(
      with: URL(string: item.asset.image),
      contentMode: item.contentMode,
      index: item.index,
      callback: item.callback
    )
  }

  private lazy var dataSource = UICollectionViewDiffableDataSource<Int, RemoteImage>(
    collectionView: imageGridView.collectionView
  ) { [weak self] collectionView, indexPath, asset in
    guard let self else { return nil }
    return collectionView.dequeueConfiguredReusableCell(
      using: self.cellRegistration,
      for: indexPath,
      item: (
        asset: asset, contentMode: indexPath.item == 0 ? .scaleAspectFit : .scaleAspectFill,
        screenScale: self.view.window?.screen.scale ?? 3, index: indexPath.item,
        callback: { self.imageGridView.firstImageAspectRatio = $0 }

      )
    )
  }

  init(remoteImages: [RemoteImage]) {
    self.remoteImages = remoteImages

    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: - Lifecycle

  override func loadView() {
    imageGridView.collectionView.delegate = self
    view = imageGridView
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    Task(priority: .high) { await setUpDataSource() }
  }

  // MARK: - Methods

  private func setUpDataSource() async {
    var snapshot = NSDiffableDataSourceSnapshot<Int, RemoteImage>()
    snapshot.appendSections([0])
    snapshot.appendItems(self.remoteImages)

    await dataSource.applySnapshotUsingReloadData(snapshot)
  }

  override var childForStatusBarHidden: UIViewController? { self.mediaViewer }

  override var childForHomeIndicatorAutoHidden: UIViewController? { self.mediaViewer }
}

// MARK: - UICollectionViewDelegate -

extension NukeImagesViewController: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    let asset = dataSource.itemIdentifier(for: indexPath)!
    let mediaViewer = CustomMediaViewerViewController(
      opening: asset,
      dataSource: self,
      parentNavigationController: self.navigationController,
      onDismiss: { self.setNeedsStatusBarAppearanceUpdate() }
    )
    self.mediaViewer = mediaViewer
    mediaViewer.mediaViewerDelegate = self

    mediaViewer.modalPresentationStyle = .overFullScreen
    mediaViewer.modalPresentationCapturesStatusBarAppearance = true
    mediaViewer.transitioningDelegate = mediaViewer

    Task {
      // put the image into the cache to have it be loaded for the transition
      if let url = URL(string: asset.imagefull) {
        _ = try? await ImagePipeline.shared.image(for: url)
      }

      present(mediaViewer, animated: true)
    }
  }
}

// MARK: - MediaViewerDataSource -

extension NukeImagesViewController: MediaViewerDataSource {
  typealias MediaIdentifier = RemoteImage

  func mediaIdentifiers(for mediaViewer: MediaViewerViewController) -> [MediaIdentifier] {
    dataSource.snapshot().itemIdentifiers
  }

  func mediaViewer(
    _ mediaViewer: MediaViewerViewController,
    mediaWith mediaIdentifier: MediaIdentifier
  ) -> Media {
    .async {
      guard let url = URL(string: mediaIdentifier.imagefull) else { return nil }

      return try? await ImagePipeline.shared.image(for: url)
    }
  }

  func mediaViewer(
    _ mediaViewer: MediaViewerViewController,
    transitionSourceViewForMediaWith mediaIdentifier: MediaIdentifier
  ) -> UIView? {
    let indexPathForCurrentImage = dataSource.indexPath(for: mediaIdentifier)!

    let collectionView = imageGridView.collectionView

    // NOTE: Without this, later cellForItem(at:) sometimes returns nil.
    if !collectionView.indexPathsForVisibleItems.contains(indexPathForCurrentImage) {
      collectionView.scrollToItem(
        at: indexPathForCurrentImage,
        at: .centeredVertically,
        animated: false
      )
    }
    collectionView.layoutIfNeeded()

    guard
      let cellForCurrentImage = collectionView.cellForItem(at: indexPathForCurrentImage)
        as? ImageCell
    else { return nil }
    return cellForCurrentImage.imageView
  }
}

// MARK: - MediaViewerDelegate -

extension NukeImagesViewController: MediaViewerDelegate {
  func mediaViewer(
    _ mediaViewer: MediaViewerViewController,
    didMoveToMediaWith mediaIdentifier: MediaIdentifier
  ) { self.mediaViewer?.overlayTitle = self.getTitle(for: mediaIdentifier) }

  func mediaViewerPageIsTransitioning(
    _ mediaViewer: MediaViewer.MediaViewerViewController,
    transitioningMedia transitioningMediaIdentifier: MediaIdentifier
  ) { self.mediaViewer?.overlayTitle = self.getTitle(for: transitioningMediaIdentifier) }

  func mediaViewerPageTapped(_ mediaViewer: MediaViewerViewController) {
    self.mediaViewer?.isShowingMediaOnly.toggle()
  }

  func mediaViewerPageDidZoom(_ mediaViewer: MediaViewerViewController, isAtMinimumScale: Bool) {
    self.mediaViewer?.isShowingMediaOnly = !isAtMinimumScale
  }

  func mediaViewerPageWillBeginDragging(_ mediaViewer: MediaViewerViewController) {
    self.mediaViewer?.isShowingMediaOnly = true
  }

  func getTitle(for mediaIdentifier: MediaIdentifier) -> String {
    let indexPathForCurrentImage = dataSource.indexPath(for: mediaIdentifier)!

    return "\(indexPathForCurrentImage.item + 1)., összesen \(indexPathForCurrentImage.count)"
  }
}

class CustomMediaViewerViewController: MediaViewerViewController {
  private lazy var overlayView: OverlayView = {
    OverlayView(onCloseButtonTap: { [weak self] in self?.dismiss(animated: true) })
  }()
  private let backgroundView = UIView()
  public var isShowingMediaOnly: Bool = false { didSet { self.updateOverlayAndBackground() } }
  public var isStatusBarHidden: Bool = false { didSet { setNeedsStatusBarAppearanceUpdate() } }
  private var isHomeIndicatorHidden = false { didSet { setNeedsUpdateOfHomeIndicatorAutoHidden() } }
  var onDismiss: () -> Void

  public init<MediaIdentifier>(
    opening mediaIdentifier: MediaIdentifier,
    dataSource: some MediaViewerDataSource<MediaIdentifier>,
    parentNavigationController: UINavigationController? = nil,
    onDismiss: @escaping () -> Void
  ) {
    self.onDismiss = onDismiss
    super
      .init(
        opening: mediaIdentifier,
        dataSource: dataSource,
        parentNavigationController: parentNavigationController
      )
  }

  override func loadView() {
    super.loadView()

    self.view.addSubview(overlayView)

    let navigationBarHeight = self.parentNavigationController?.navigationBar.frame.height ?? 44

    overlayView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      overlayView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      overlayView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
      overlayView.heightAnchor.constraint(equalToConstant: navigationBarHeight),
    ])

    self.view.insertSubview(self.backgroundView, at: 0)

    self.backgroundView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      self.backgroundView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      self.backgroundView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      self.backgroundView.topAnchor.constraint(equalTo: self.view.topAnchor),
      self.backgroundView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
    ])

    self.isShowingMediaOnly = false
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    self.onDismiss()
  }

  override var prefersStatusBarHidden: Bool { isStatusBarHidden }

  override var prefersHomeIndicatorAutoHidden: Bool { isHomeIndicatorHidden }

  var overlayTitle: String? {
    get { self.overlayView.title }
    set { self.overlayView.title = newValue }
  }

  private func updateOverlayAndBackground() {
    if !self.isShowingMediaOnly {
      self.overlayView.isHidden = false
      self.overlayView.alpha = 0
    }

    UIView.animate(withDuration: 0.1, delay: 0.05) {
      self.overlayView.alpha = self.isShowingMediaOnly ? 0 : 1
      self.backgroundView.backgroundColor =
        self.isShowingMediaOnly ? .black : .init(light: .white, dark: .black)
      self.isStatusBarHidden = self.isShowingMediaOnly
      self.isHomeIndicatorHidden = self.isShowingMediaOnly
    } completion: { _ in
      self.overlayView.isHidden = self.isShowingMediaOnly
    }
  }

  class OverlayView: UIView {
    private lazy var stackView: UIStackView = {
      let stackView = UIStackView(arrangedSubviews: [
        self.spacerView, self.titleLabel, self.closeButton,
      ])
      stackView.axis = .horizontal
      stackView.alignment = .center
      stackView.distribution = .equalCentering
      stackView.translatesAutoresizingMaskIntoConstraints = false

      return stackView
    }()
    private lazy var spacerView: UIView = {
      let view = UIView()
      view.translatesAutoresizingMaskIntoConstraints = false

      return view
    }()
    private lazy var closeButton: UIButton = {
      let button = UIButton(
        type: .custom,
        primaryAction: UIAction(handler: { [weak self] _ in self?.onCloseButtonTap() })
      )

      var config = UIButton.Configuration.plain()
      config.image = UIImage(systemName: "xmark.circle.fill")
      config.baseForegroundColor = .label
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        font: .preferredFont(forTextStyle: .title2)
      )
      config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
      button.configuration = config
      button.translatesAutoresizingMaskIntoConstraints = false

      return button
    }()
    private let blurView: UIView = {
      let blurEffect = UIBlurEffect(style: .systemChromeMaterial)
      let blurView = UIVisualEffectView(effect: blurEffect)
      blurView.translatesAutoresizingMaskIntoConstraints = false

      return blurView
    }()
    private lazy var titleLabel: UILabel = {
      let label = UILabel()
      label.textAlignment = .center

      return label
    }()
    private var constraintsInitialized = false
    private let onCloseButtonTap: () -> Void

    init(onCloseButtonTap: @escaping () -> Void) {
      self.onCloseButtonTap = onCloseButtonTap

      super.init(frame: .zero)

      self.layer.zPosition = 1  // have this view go over the transitioning view

      self.addSubview(self.stackView)
      self.insertSubview(blurView, at: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setupContraints(superview: UIView) {
      NSLayoutConstraint.activate([
        self.spacerView.widthAnchor.constraint(equalTo: self.closeButton.widthAnchor),

        self.blurView.topAnchor.constraint(equalTo: superview.topAnchor),
        self.blurView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        self.blurView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        self.blurView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

        self.stackView.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor),
        self.stackView.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor),
        self.stackView.topAnchor.constraint(equalTo: self.topAnchor),
        self.stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
      ])
    }

    override func didMoveToSuperview() {
      super.didMoveToSuperview()

      guard !self.constraintsInitialized, let superview else { return }

      self.setupContraints(superview: superview)

      self.constraintsInitialized = true
    }

    var title: String? {
      get { self.titleLabel.text }
      set { self.titleLabel.text = newValue }
    }
  }

}

public struct RemoteImage: Codable, Equatable, Sendable, Identifiable, Hashable {
  public let id: UUID
  public let image: String
  public let imagefull: String

  public init(id: UUID = UUID(), image: String, imagefull: String) {
    self.id = id
    self.image = image
    self.imagefull = imagefull
  }
}

extension ImageCell {
  func configure(
    with url: URL?,
    contentMode: UIView.ContentMode,
    index: Int,
    callback: @escaping (CGFloat) -> Void
  ) {
    self.imageView.contentMode = contentMode

    Task {
      self.imageView.image =
        if let url { try? await ImagePipeline.shared.image(for: url) } else { nil }

      if index == 0, let size = self.imageView.image?.size {
        let firstImageAspectRatio = size.width / size.height
        callback(firstImageAspectRatio)
      }
    }
  }
}

extension UIColor {
  convenience init(
    light lightModeColor: @escaping @autoclosure () -> UIColor,
    dark darkModeColor: @escaping @autoclosure () -> UIColor
  ) {
    self.init { traitCollection in
      switch traitCollection.userInterfaceStyle {
      case .dark: darkModeColor()
      case .light, .unspecified: lightModeColor()
      @unknown default: lightModeColor()
      }
    }
  }
}
