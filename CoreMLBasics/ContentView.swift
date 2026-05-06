//
//  ContentView.swift
//  CoreMLBasics
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ImageClassifierView()
                .tabItem {
                    Label("이미지 분류", systemImage: "photo")
                }

            ScannerView()
                .tabItem {
                    Label("QR / 텍스트", systemImage: "qrcode.viewfinder")
                }

            IdentityVerificationView()
                .tabItem {
                    Label("인증 보조", systemImage: "person.crop.rectangle")
                }
        }
    }
}

#Preview {
    ContentView()
}
