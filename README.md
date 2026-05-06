# CoreMLBasics

iOS 앱에서 Apple의 Core ML, Vision, Natural Language 프레임워크를 활용해 온디바이스 AI 기능을 구현하는 프로젝트입니다. 서버 호출 없이 기기에서 직접 추론하는 구조로, 프라이버시와 응답 속도를 모두 챙깁니다.

## 기술 스택

- Swift / SwiftUI
- Core ML
- Vision Framework
- AVFoundation
- Natural Language Framework
- OpenAI API

---

## Task 1. 이미지 분류 (Core ML + Vision)

MobileNetV2 모델을 앱 번들에 포함해 갤러리 이미지를 온디바이스로 분류합니다.

**구현 내용**
- `VNCoreMLModel` + `VNCoreMLRequest` + `VNImageRequestHandler` 파이프라인 구성
- `async/await` 기반 비동기 추론 처리
- Top-5 분류 결과 및 신뢰도 시각화
- 추론 소요 시간 측정

**핵심 구조**
```swift
let model = try VNCoreMLModel(for: MobileNetV2().model)
let request = VNCoreMLRequest(model: model) { ... }
try VNImageRequestHandler(cgImage: img).perform([request])
```

| | LLM API (서버) | Core ML (온디바이스) |
|---|---|---|
| 네트워크 | 필요 | 불필요 |
| 프라이버시 | 데이터 외부 전송 | 기기 밖으로 안 나감 |
| 비용 | 토큰당 과금 | 무료 |
| 속도 | 네트워크 지연 | 10~100ms |

---

## Task 2. 실시간 QR / 텍스트 인식 (Vision Framework)

AVCaptureSession으로 카메라 피드를 받아 Vision 요청을 실시간으로 처리합니다.

**구현 내용**
- `AVCaptureSession` + `AVCaptureVideoDataOutput` 파이프라인 구성
- `VNDetectBarcodesRequest` — QR코드, 바코드 실시간 감지 및 데이터 추출
- `VNRecognizeTextRequest` — 실시간 OCR (한국어/영어 지원)
- `UIViewRepresentable`로 SwiftUI ↔ AVCaptureVideoPreviewLayer 브릿지
- Vision 좌표계 → SwiftUI 좌표계 변환, 감지 영역 오버레이 표시

**좌표 변환**
```swift
// Vision: 좌하단 원점, Y↑  →  SwiftUI: 좌상단 원점, Y↓
let y = (1 - visionRect.maxY) * frameHeight
```

---

## Task 3. 얼굴 인식 + 신분증 스캔 (Vision 심화)

얼굴 랜드마크 추출과 문서 감지 기반 신분증 스캔을 구현하고, OCR 결과를 LLM API로 연결해 정보를 구조화합니다.

**구현 내용**
- `VNDetectFaceLandmarksRequest` — 얼굴 위치 + 눈/코/입/윤곽 68개 랜드마크 포인트 추출
- `VNDetectDocumentSegmentationRequest` — 신분증 외곽 감지 및 영역 크롭 (iOS 15+)
- 크롭된 문서 영역에 `VNRecognizeTextRequest` 적용해 OCR 정확도 향상
- OCR 원문을 OpenAI API(JSON mode)로 넘겨 이름/생년월일/주소 구조화 파싱
- 얼굴 랜드마크 포인트 SwiftUI 오버레이 시각화

**랜드마크 좌표 변환**
```swift
// 랜드마크는 얼굴 boundingBox 기준 로컬 좌표 → 두 단계 변환 필요
let globalX = faceBBox.minX + localPoint.x * faceBBox.width
let globalY = faceBBox.minY + localPoint.y * faceBBox.height
// 이후 Vision → SwiftUI Y축 반전 적용
```

**Vision(온디바이스) + LLM API 연결 구조**
```
신분증 사진 → VNDetectDocumentSegmentation(크롭) → VNRecognizeText(OCR) → OpenAI API(파싱) → DocumentInfo
```
