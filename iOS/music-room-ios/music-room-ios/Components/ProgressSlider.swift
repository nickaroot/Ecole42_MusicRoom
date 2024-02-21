//
//  ProgressSlider.swift
//  music-room-ios
//
//  Created by Nikita Arutyunov on 13.07.2022.
//

import SwiftUI

struct ProgressSlider: View {
    
    @Binding
    var trackProgress: ViewModel.TrackProgress
    
    @Binding
    var isTracking: Bool
    
    @Binding
    var isLoadingProgress: Bool
    
    @Binding
    var initialValue: Double?
    
    @Binding
    var animatingPadding: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(.accentColor.opacity(0.3))
                
                Rectangle()
                    .foregroundColor(.accentColor.opacity(0.2))
                    .frame(
                        width: {
                            guard
                                let buffer = trackProgress.buffers?.first,
                                let total = trackProgress.total,
                                total != 0
                            else {
                                return 0
                            }
                            
                            let lastValue = buffer.start + buffer.duration
                            
                            return geometry.size.width * CGFloat(lastValue / total)
                        }()
                    )
                
                Rectangle()
                    .foregroundColor(isTracking ? .accentColor : .accentColor.opacity(0.7))
                    .frame(
                        width: {
                            guard
                                let value = trackProgress.value,
                                let total = trackProgress.total,
                                total != 0
                            else {
                                return 0
                            }
                            
                            return geometry.size.width * CGFloat(value / total)
                        }()
                    )
            }
            .frame(height: isTracking ? 8 : 4)
            .cornerRadius(isTracking ? 4 : 2)
            .padding(.vertical, isTracking ? 0 : 2)
            .animation(.easeIn(duration: 0.18), value: animatingPadding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isTracking {
                            isTracking = true
                            
                            if initialValue == nil {
                                initialValue = trackProgress.value
                            }
                        }
                        
                        guard
                            let value = initialValue,
                            let total = trackProgress.total,
                            total != 0
                        else {
                            return
                        }
                        
                        let trackProgressPercentage = value / total
                        let translationPercentage = gesture.translation.width / geometry.size.width
                        
                        let percentage = max(
                            0,
                            min(
                                1,
                                trackProgressPercentage + translationPercentage
                            )
                        )
                        
                        trackProgress = ViewModel.TrackProgress(
                            value: total * percentage,
                            total: total,
                            buffers: trackProgress.buffers
                        )
                    }
                    .onEnded { gesture in
                        defer {
                            isTracking = false
                            isLoadingProgress = true
                            initialValue = nil
                        }
                        
                        guard
                            let value = initialValue,
                            let total = trackProgress.total,
                            total != 0
                        else {
                            return
                        }
                        
                        let translationPercentage = gesture.translation.width / geometry.size.width
                        
                        let newValue = max(
                            0,
                            min(
                                total,
                                value + (total * translationPercentage).rounded()
                            )
                        )
                        
                        trackProgress = ViewModel.TrackProgress(
                            value: newValue,
                            total: total,
                            buffers: trackProgress.buffers
                        )
                    }
            )
        }
    }
}
