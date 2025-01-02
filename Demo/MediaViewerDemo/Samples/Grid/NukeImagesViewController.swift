import MediaViewer
import Nuke
import UIKit

final class NukeImagesViewController: UIViewController {
  let remoteImages: [RemoteImage]

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

  private weak var mediaViewer: MediaViewerViewController?
  private var overlayView: OverlayView?
  private let backgroundView = UIView()
  private var isShowingMediaOnly: Bool = false { didSet { self.updateOverlayAndBackground() } }

  func updateTitle() {
    guard let mediaViewer, let overlayView else { return }

    let mediaIdentifier =
      mediaViewer.pendingMediaIdentifier(as: MediaIdentifier.self)
      ?? mediaViewer.currentMediaIdentifier(as: MediaIdentifier.self)

    let indexPathForCurrentImage = dataSource.indexPath(for: mediaIdentifier)!
    overlayView.title =
      "\(indexPathForCurrentImage.item + 1)., összesen \(indexPathForCurrentImage.count)"
  }

  private func updateOverlayAndBackground() {
    guard let mediaViewer, let overlayView else { return }

    if !self.isShowingMediaOnly {
      overlayView.isHidden = false
      overlayView.alpha = 0
    }

    UIView.animate(withDuration: 0.1, delay: 0.05) {
      overlayView.alpha = self.isShowingMediaOnly ? 0 : 1
      self.backgroundView.backgroundColor =
        self.isShowingMediaOnly ? .black : .init(light: .white, dark: .black)
      mediaViewer.isStatusBarHidden = self.isShowingMediaOnly
      self.isHomeIndicatorHidden = self.isShowingMediaOnly
    } completion: { _ in
      overlayView.isHidden = self.isShowingMediaOnly
    }
  }

  var isHomeIndicatorHidden = false { didSet { setNeedsUpdateOfHomeIndicatorAutoHidden() } }

  override var prefersHomeIndicatorAutoHidden: Bool { isHomeIndicatorHidden }
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
      primaryAction: UIAction(handler: { _ in self.onCloseButtonTap() })
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

// MARK: - UICollectionViewDelegate -

extension NukeImagesViewController: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    let asset = dataSource.itemIdentifier(for: indexPath)!
    let mediaViewer = MediaViewerViewController(opening: asset, dataSource: self)
    self.mediaViewer = mediaViewer
    mediaViewer.mediaViewerDelegate = self

    mediaViewer.modalPresentationStyle = .overCurrentContext
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
  func mediaIdentifiers(for mediaViewer: MediaViewerViewController) -> [RemoteImage] {
    dataSource.snapshot().itemIdentifiers
  }

  func mediaViewer(_ mediaViewer: MediaViewerViewController, mediaWith mediaIdentifier: RemoteImage)
    -> Media
  {
    .async {
      guard let url = URL(string: mediaIdentifier.imagefull) else { return nil }

      return try? await ImagePipeline.shared.image(for: url)
    }
  }

  func mediaViewer(
    _ mediaViewer: MediaViewerViewController,
    transitionSourceViewForMediaWith mediaIdentifier: RemoteImage
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
    willBeginPopTransitionTo destinationVC: UIViewController
  ) {
    self.mediaViewer = nil
    self.overlayView = nil
    self.isShowingMediaOnly = false
  }

  func mediaViewer(
    _ mediaViewer: MediaViewerViewController,
    didMoveToMediaWith mediaIdentifier: MediaIdentifier
  ) {
    guard overlayView == nil else { return }

    let overlayView = OverlayView(onCloseButtonTap: { self.dismiss(animated: true) })
    self.overlayView = overlayView

    let mediaViewerView = mediaViewer.view!

    mediaViewer.view.addSubview(overlayView)

    let navigationBarHeight = self.navigationController?.navigationBar.frame.height ?? 44

    overlayView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      overlayView.leadingAnchor.constraint(equalTo: mediaViewerView.leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: mediaViewerView.trailingAnchor),
      overlayView.topAnchor.constraint(equalTo: mediaViewerView.safeAreaLayoutGuide.topAnchor),
      overlayView.heightAnchor.constraint(equalToConstant: navigationBarHeight),
    ])

    self.updateTitle()

    mediaViewerView.insertSubview(self.backgroundView, at: 0)

    self.backgroundView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      backgroundView.topAnchor.constraint(equalTo: mediaViewerView.topAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: mediaViewerView.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: mediaViewerView.trailingAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: mediaViewerView.bottomAnchor),
    ])

    self.isShowingMediaOnly = false
  }

  func mediaViewerPageIsTransitioning(_ mediaViewer: MediaViewerViewController) {
    self.updateTitle()
  }

  func mediaViewerPageTapped(_ mediaViewer: MediaViewerViewController) {
    self.isShowingMediaOnly.toggle()
  }

  func mediaViewerPageDidZoom(_ mediaViewer: MediaViewerViewController, isAtMinimumScale: Bool) {
    self.isShowingMediaOnly = !isAtMinimumScale
  }

  func mediaViewerPageWillBeginDragging(_ mediaViewer: MediaViewerViewController) {
    self.isShowingMediaOnly = true
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
