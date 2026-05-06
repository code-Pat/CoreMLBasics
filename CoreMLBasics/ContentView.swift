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

            TextAnalysisView()
                .tabItem {
                    Label("텍스트 분석", systemImage: "text.word.spacing")
                }

            OnDeviceLLMView()
                .tabItem {
                    Label("온디바이스 LLM", systemImage: "brain")
                }

            PipelineView()
                .tabItem {
                    Label("파이프라인", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
        }
    }
}

#Preview {
    ContentView()
}
