//
//  BoringAnimationPhysics.swift
//  Mac灵动岛
//
//  Reverse-engineered from Boring.notch codebase
//  This file contains the EXACT animation physics parameters extracted from the source
//
//  Created by Animation Extraction on 2026-01-24
//

import SwiftUI

// MARK: - Interactive Spring Constants
// Source: boring.notch/boringNotch/ContentView.swift line 41

/// The shared interactive spring used for ALL movement/resizing
/// This is the "magnetic" feel that makes interactions feel connected
///
/// Parameters extracted:
/// - response: 0.38 (how quickly the spring responds)
/// - dampingFraction: 0.8 (controls oscillation - 0.8 is slightly underdamped)
/// - blendDuration: 0 (instant blend between animations)
let boringInteractiveSpring = Animation.interactiveSpring(
    response: 0.38,
    dampingFraction: 0.8,
    blendDuration: 0
)

// MARK: - State Transition Springs
// Source: boring.notch/boringNotch/ContentView.swift lines 123-124

/// Opening animation spring - slightly faster response
/// Used when the notch expands from compact to open state
let boringOpenAnimation = Animation.spring(
    response: 0.42,          // Slightly slower than interactive
    dampingFraction: 0.8,    // Same damping maintains consistency
    blendDuration: 0
)

/// Closing animation spring - higher damping for controlled return
/// Used when the notch contracts from open to compact state
let boringCloseAnimation = Animation.spring(
    response: 0.45,          // Slightly slower for smooth settle
    dampingFraction: 1.0,    // Critical damping - no oscillation
    blendDuration: 0
)
