//
//  CameraPreviewView.swift
//  CoreMLBasics
//
//  Created by Donggeun Lee on 5/6/26.
//

import SwiftUI
import AVFoundation
import Vision
 
// MARK: - 카메라 미리보기 (UIViewRepresentable)
// UIViewRepresentable: SwiftUI에서 UIView를 사용하는 브릿지 프로토콜
// AVCaptureVideoPreviewLayer는 UIKit 전용이라 이 패턴 필수
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
 
    // makeUIView: 최초 한 번 호출 — UIView 생성
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }
 
    // updateUIView: SwiftUI 상태가 바뀔 때마다 호출
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
 
// AVCaptureVideoPreviewLayer를 담는 UIView
class PreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session = session else { return }
            previewLayer.session = session
        }
    }
 
    // UIView의 기본 레이어를 AVCaptureVideoPreviewLayer로 교체
    // 이 방식이 CALayer를 addSublayer로 추가하는 것보다 안정적
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
 
    private var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
 
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
    }
}
 
// MARK: - 오버레이 뷰 (Vision 결과를 화면에 그리기)
struct ScanOverlayView: View {
    let result: ScanResult
    let frameSize: CGSize  // 실제 카메라 미리보기 크기
 
    var body: some View {
        ZStack {
            // QR코드 / 바코드 박스
            ForEach(result.barcodes) { barcode in
                BarcodeOverlay(barcode: barcode, frameSize: frameSize)
            }
 
            // 텍스트 박스
            ForEach(result.texts) { text in
                TextOverlay(text: text, frameSize: frameSize)
            }
        }
    }
}
 
// MARK: - 바코드 오버레이
struct BarcodeOverlay: View {
    let barcode: BarcodeResult
    let frameSize: CGSize
 
    var body: some View {
        let rect = convertVisionRect(barcode.boundingBox, to: frameSize)
 
        return ZStack(alignment: .topLeading) {
            // 감지 박스
            Rectangle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
 
            // 내용 태그
            Text(barcode.payload)
                .font(.caption2)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(y: -20)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}
 
// MARK: - 텍스트 오버레이
struct TextOverlay: View {
    let text: TextResult
    let frameSize: CGSize
 
    var body: some View {
        let rect = convertVisionRect(text.boundingBox, to: frameSize)
 
        return Rectangle()
            .stroke(Color.blue.opacity(0.7), lineWidth: 1)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}
 
// MARK: - 핵심: Vision 좌표 → SwiftUI 좌표 변환
// ⚠️ 이 함수가 Week 3~4 가장 중요한 포인트
//
// Vision 좌표계:          SwiftUI/UIKit 좌표계:
// 원점: 좌하단            원점: 좌상단
// Y축: 위로 증가 ↑       Y축: 아래로 증가 ↓
// 값 범위: 0.0 ~ 1.0     값 범위: 0 ~ frameSize
//
// 변환 공식:
// x = visionBox.minX * width
// y = (1 - visionBox.maxY) * height  ← Y 반전이 핵심
func convertVisionRect(_ visionRect: CGRect, to frameSize: CGSize) -> CGRect {
    let x = visionRect.minX * frameSize.width
    let y = (1 - visionRect.maxY) * frameSize.height  // Y축 반전
    let w = visionRect.width * frameSize.width
    let h = visionRect.height * frameSize.height
    return CGRect(x: x, y: y, width: w, height: h)
}
