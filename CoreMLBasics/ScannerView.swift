//
//  ScannerView.swift
//  CoreMLBasics
//
//  Created by Donggeun Lee on 5/6/26.
//

import SwiftUI
 
struct ScannerView: View {
    @StateObject private var cameraService = CameraService()
    @State private var selectedTab = 0  // 0: QR, 1: 텍스트
 
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
 
                // MARK: - 카메라 뷰 (상단 60%)
                GeometryReader { geo in
                    ZStack {
                        // 1. 카메라 미리보기
                        if cameraService.isAuthorized {
                            CameraPreviewView(session: cameraService.captureSession)
                                .ignoresSafeArea()
                        } else {
                            // 권한 없을 때 안내
                            cameraPermissionView
                        }
 
                        // 2. Vision 결과 오버레이
                        ScanOverlayView(
                            result: cameraService.scanResult,
                            frameSize: geo.size
                        )
 
                        // 3. 스캔 가이드 프레임
                        scanGuideOverlay
                    }
                }
                .frame(height: UIScreen.main.bounds.height * 0.55)
 
                Divider()
 
                // MARK: - 결과 패널 (하단)
                VStack(spacing: 0) {
                    // 탭 선택
                    Picker("결과 타입", selection: $selectedTab) {
                        Text("QR / 바코드").tag(0)
                        Text("텍스트 OCR").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
 
                    // 결과 표시
                    if selectedTab == 0 {
                        BarcodeResultsPanel(barcodes: cameraService.scanResult.barcodes)
                    } else {
                        TextResultsPanel(texts: cameraService.scanResult.texts)
                    }
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("Vision 스캐너")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 결과 초기화 버튼
                    Button {
                        cameraService.scanResult = ScanResult()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .onDisappear {
            cameraService.stopSession()
        }
    }
 
    // MARK: - 서브뷰
 
    private var scanGuideOverlay: some View {
        // 중앙 스캔 가이드 박스 (UX 힌트)
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.6), lineWidth: 2)
            .frame(width: 220, height: 220)
            .overlay {
                Text("여기에 QR 또는 텍스트를 위치시키세요")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(width: 160)
                    .offset(y: 125)
            }
    }
 
    private var cameraPermissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("카메라 접근 권한이 필요합니다")
                .foregroundStyle(.secondary)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8))
    }
}
 
// MARK: - QR/바코드 결과 패널
struct BarcodeResultsPanel: View {
    let barcodes: [BarcodeResult]
 
    var body: some View {
        Group {
            if barcodes.isEmpty {
                emptyStateView(icon: "qrcode.viewfinder", message: "QR코드나 바코드를 카메라에 비춰보세요")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(barcodes) { barcode in
                            BarcodeResultCard(barcode: barcode)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
 
struct BarcodeResultCard: View {
    let barcode: BarcodeResult
 
    var body: some View {
        HStack(spacing: 12) {
            // 코드 타입 아이콘
            Image(systemName: barcode.symbology.contains("QR") ? "qrcode" : "barcode")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 36)
 
            VStack(alignment: .leading, spacing: 2) {
                Text(barcode.symbology)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(barcode.payload)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
 
            Spacer()
 
            // 복사 버튼
            Button {
                UIPasteboard.general.string = barcode.payload
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
 
// MARK: - 텍스트 OCR 결과 패널
struct TextResultsPanel: View {
    let texts: [TextResult]
 
    var body: some View {
        Group {
            if texts.isEmpty {
                emptyStateView(icon: "text.viewfinder", message: "텍스트가 있는 곳을 카메라에 비춰보세요")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // 전체 텍스트 합치기 (읽기 쉽게)
                        let fullText = texts.map(\.text).joined(separator: " ")
                        Text(fullText)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
 
                        // 개별 인식 결과
                        Text("개별 인식 결과 (\(texts.count)개)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
 
                        ForEach(texts) { textResult in
                            HStack {
                                Text(textResult.text)
                                    .font(.caption)
                                Spacer()
                                Text(String(format: "%.0f%%", textResult.confidence * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
    }
}
 
// 공통 빈 상태 뷰
private func emptyStateView(icon: String, message: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: icon)
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
}
 
#Preview {
    ScannerView()
}
 
