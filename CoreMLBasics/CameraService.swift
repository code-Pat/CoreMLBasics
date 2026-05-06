//
//  CameraService.swift
//  CoreMLBasics
//
//  Created by Donggeun Lee on 5/6/26.
//

import AVFoundation
import Vision
import UIKit
import Combine
 
// Vision 결과를 담는 통합 모델
struct ScanResult {
    var barcodes: [BarcodeResult] = []
    var texts: [TextResult] = []
}
 
struct BarcodeResult: Identifiable {
    let id = UUID()
    let payload: String          // QR코드 내용 (URL, 텍스트 등)
    let symbology: String        // 코드 종류 (QR, EAN-13 등)
    let boundingBox: CGRect      // Vision 좌표계 (0~1 정규화, 좌하단 원점)
}
 
struct TextResult: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect      // Vision 좌표계
    let confidence: Float
}
 
// MARK: - CameraService
// ObservableObject: SwiftUI가 결과 변화를 감지해서 UI 자동 업데이트
class CameraService: NSObject, ObservableObject {
 
    // MARK: Published 상태
    @Published var scanResult = ScanResult()
    @Published var isAuthorized = false
    @Published var errorMessage: String?
 
    // MARK: AV 설정
    let captureSession = AVCaptureSession()
 
    // Vision 처리 전용 큐 — 메인 스레드 절대 사용 금지
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let visionQueue = DispatchQueue(label: "vision.processing")
 
    // MARK: - 초기화
    override init() {
        super.init()
        checkAuthorization()
    }
 
    // MARK: - 카메라 권한 확인
    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            // 최초 실행 시 권한 요청
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            isAuthorized = false
        }
    }
 
    // MARK: - 세션 설정
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
 
            self.captureSession.beginConfiguration()
 
            // Step 1: 후면 카메라 입력 설정
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.errorMessage = "카메라를 사용할 수 없어요"
                }
                return
            }
            self.captureSession.addInput(input)
 
            // Step 2: 비디오 출력 설정
            // AVCaptureVideoDataOutput: 카메라 프레임을 CMSampleBuffer로 전달해줌
            let output = AVCaptureVideoDataOutput()
 
            // visionQueue에서 프레임 처리 — 메인 스레드 블로킹 방지
            // ⚠️ 학습 포인트: Vision 처리를 메인 스레드에서 하면 UI 버벅거림
            output.setSampleBufferDelegate(self, queue: self.visionQueue)
 
            // 이전 프레임이 처리 중일 때 새 프레임은 버림 (Vision 처리 속도가 프레임 레이트보다 느릴 때)
            output.alwaysDiscardsLateVideoFrames = true
 
            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
            }
 
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }
 
    // MARK: - 세션 제어
    func startSession() {
        sessionQueue.async { [weak self] in
            if !(self?.captureSession.isRunning ?? true) {
                self?.captureSession.startRunning()
            }
        }
    }
 
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
}
 
// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// 카메라 프레임이 들어올 때마다 이 메서드가 호출됨 (~30fps)
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
 
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
 
        // CMSampleBuffer → CGImage 변환
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
 
        // Step 3: VNImageRequestHandler 생성
        // .leftMirrored: 전면 카메라 좌우 반전 보정 (후면 카메라엔 .up)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
 
        // 두 요청을 동시에 실행 — Vision이 내부적으로 최적화
        let requests: [VNRequest] = [makeBarcodeRequest(), makeTextRequest()]
 
        do {
            // Step 4: 요청 실행 — visionQueue에서 실행 중 (CameraService 초기화 시 설정)
            try handler.perform(requests)
        } catch {
            print("Vision 처리 실패: \(error)")
        }
    }
 
    // MARK: - QR/바코드 요청
    private func makeBarcodeRequest() -> VNDetectBarcodesRequest {
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let observations = request.results as? [VNBarcodeObservation],
                  !observations.isEmpty else { return }
 
            let results = observations.compactMap { obs -> BarcodeResult? in
                guard let payload = obs.payloadStringValue else { return nil }
 
                // symbology를 읽기 쉬운 문자열로 변환
                let symbology = obs.symbology.rawValue
                    .replacingOccurrences(of: "VNBarcodeSymbology", with: "")
 
                return BarcodeResult(
                    payload: payload,
                    symbology: symbology,
                    boundingBox: obs.boundingBox  // Vision 좌표계 그대로 저장
                )
            }
 
            // UI 업데이트는 반드시 메인 스레드에서
            DispatchQueue.main.async {
                self?.scanResult.barcodes = results
            }
        }
 
        // 인식할 코드 종류 제한 (생략하면 모든 종류 인식 — 성능 비용 있음)
        request.symbologies = [.qr, .ean13, .ean8, .code128]
        return request
    }
 
    // MARK: - 텍스트 인식 요청
    private func makeTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  !observations.isEmpty else { return }
 
            let results = observations.compactMap { obs -> TextResult? in
                // topCandidates(1): 가장 신뢰도 높은 후보 1개
                guard let candidate = obs.topCandidates(1).first,
                      candidate.confidence > 0.5 else { return nil }  // 낮은 신뢰도 필터링
 
                return TextResult(
                    text: candidate.string,
                    boundingBox: obs.boundingBox,
                    confidence: candidate.confidence
                )
            }
 
            DispatchQueue.main.async {
                self?.scanResult.texts = results
            }
        }
 
        // 인식 수준: .accurate (정확) vs .fast (빠름)
        // 실시간 처리엔 .fast, 정지 이미지엔 .accurate 권장
        request.recognitionLevel = .fast
 
        // ⚠️ 학습 포인트: 언어 명시 안 하면 한글 인식률 떨어짐
        request.recognitionLanguages = ["ko-KR", "en-US"]
 
        // 자동 언어 감지 끄기 (명시적 언어 설정과 충돌 방지)
        request.usesLanguageCorrection = true
 
        return request
    }
}
