//
//  ImageGridView.swift
//  MediaViewerDemo
//
//  Created by Yusaku Nishi on 2023/03/05.
//

import UIKit
import AceLayout

final class ImageGridView: UIView {
    var firstImageAspectRatio: CGFloat = 1.0 {
        didSet {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            let minimumItemWidth: CGFloat
            let itemSpacing: CGFloat
            let contentInsetsReference: UIContentInsetsReference
            switch layoutEnvironment.traitCollection.horizontalSizeClass {
            case .unspecified, .compact:
                minimumItemWidth = 80
                itemSpacing = 4
                contentInsetsReference = .automatic
            case .regular:
                minimumItemWidth = 100
                itemSpacing = 16
                contentInsetsReference = .layoutMargins
            @unknown default:
                fatalError()
            }
            
            let effectiveFullWidth = layoutEnvironment.container.effectiveContentSize.width
            let columnCount = Int(effectiveFullWidth / minimumItemWidth)
            let totalSpacing = itemSpacing * CGFloat(columnCount - 1)
            let estimatedItemWidth = (effectiveFullWidth - totalSpacing) / CGFloat(columnCount)

            let firstImageHeight = effectiveFullWidth / self.firstImageAspectRatio

            let largeGroup = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(firstImageHeight)
                ),
                repeatingSubitem: .init(layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(firstImageHeight)
                )),
                count: 1
            )

            let gridGroup = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalWidth(1)
                ),
                repeatingSubitem: .init(layoutSize: .init(
                    widthDimension: .fractionalWidth(1 / CGFloat(columnCount)),
                    heightDimension: .fractionalWidth(1 / CGFloat(columnCount))
                )),
                count: columnCount
            )
            gridGroup.interItemSpacing = .fixed(itemSpacing)

            let combinedGroup = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(estimatedItemWidth * CGFloat(columnCount) + estimatedItemWidth * 0.5)
                ),
                subitems: [largeGroup, gridGroup]
            )
            combinedGroup.interItemSpacing = .fixed(itemSpacing)
            
            let section = NSCollectionLayoutSection(group: combinedGroup)
            section.interGroupSpacing = itemSpacing
            section.contentInsetsReference = contentInsetsReference
            return section
        }
        
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.preservesSuperviewLayoutMargins = true
        return collectionView
    }()
    
    // MARK: - Initializers
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViews()
    }
    
    private func setUpViews() {
        preservesSuperviewLayoutMargins = true
        backgroundColor = .systemBackground
        
        // Subviews
        addSubview(collectionView)
        
        // Layout
        collectionView.autoLayout { item in
            item.edges.equalToSuperview()
        }
    }
}
