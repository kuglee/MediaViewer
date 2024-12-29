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
}

// MARK: - UICollectionViewDelegate -

extension NukeImagesViewController: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    let asset = dataSource.itemIdentifier(for: indexPath)!
    let mediaViewer = MediaViewerViewController(opening: asset, dataSource: self)
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

extension NukeImagesViewController: MediaViewerDelegate {}

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
