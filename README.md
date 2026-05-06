# CoreMLBasics

iOS 앱에서 Apple의 Core ML, Vision, Natural Language 프레임워크를 활용해 온디바이스 AI 기능을 구현하는 프로젝트입니다. 서버 호출 없이 기기에서 직접 추론하는 구조로, 프라이버시와 응답 속도를 모두 챙깁니다.

## 시작하기

OpenAI API 키가 필요합니다. 프로젝트 루트에 `Secrets.xcconfig` 파일을 생성하고 아래 내용을 추가하세요. (이 파일은 `.gitignore`에 포함되어 있습니다.)

```
OPENAI_API_KEY = your_api_key_here
```

## 기술 스택

- Swift / SwiftUI
- Core ML
- Vision Framework
- AVFoundation
- Natural Language Framework
- Foundation Models Framework
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

---

## Task 4. 텍스트 분석 (Natural Language Framework)

OCR로 추출한 텍스트를 온디바이스 NLP 파이프라인으로 처리합니다.

**구현 내용**
- `NLLanguageRecognizer` — 다국어 텍스트 언어 자동 감지 및 확신도 순위
- `NLTokenizer` — 단어/문장/문단 단위 토큰화 및 통계 집계
- `NLTagger` (.nameType 스킴) — 인물·장소·기관 개체명 인식(NER), `.joinNames` 옵션으로 복합 고유명사 결합
- `NLEmbedding` — 문장 임베딩 기반 코사인 유사도 계산, 한국어는 wordEmbedding 폴백

**핵심 구조**
```swift
// NER: 언어 힌트 주입 후 .nameType 스킴으로 열거
let tagger = NLTagger(tagSchemes: [.nameType])
tagger.setLanguage(dominant, range: fullRange)
tagger.enumerateTags(..., scheme: .nameType, options: [.omitWhitespace, .joinNames]) { tag, range in ... }

// 유사도: sentence → word 임베딩 폴백
NLEmbedding.sentenceEmbedding(for: language) ?? NLEmbedding.wordEmbedding(for: language)
```

---

## Task 5. 온디바이스 LLM (Foundation Models Framework)

Apple Intelligence의 온디바이스 LLM을 앱에서 직접 호출합니다. 네트워크 없이 기기에서 추론하며, Swift 타입 시스템과 긴밀하게 통합된 구조화 출력을 지원합니다.

**구현 내용**
- `LanguageModelSession` — 시스템 프롬프트(trailing closure) + 대화 컨텍스트 관리
- `streamResponse(to:)` — 토큰 단위 스트리밍, ChatGPT와 동일한 UX를 온디바이스로 구현
- `@Generable` + `@Guide` — constrained decoding으로 Swift 타입 직접 생성 (JSON 파싱 불필요)
- `SystemLanguageModel.default.availability` — Apple Intelligence 가용 여부 런타임 체크

**핵심 구조**
```swift
// 스트리밍 채팅
let session = LanguageModelSession { "시스템 프롬프트" }
let stream = session.streamResponse(to: userInput)
for try await partial in stream { text = partial.content }

// @Generable 구조화 출력
@Generable struct TextInsight {
    @Guide(description: "감정: positive / negative / neutral") var sentiment: String
    var keywords: [String]
    var summary: String
}
let insight = try await session.respond(to: prompt, generating: TextInsight.self).content
```

| | Phase 1 (OpenAI API) | Task 5 (Foundation Models) |
|---|---|---|
| 추론 위치 | 서버 | 온디바이스 |
| 네트워크 | 필요 | 불필요 |
| 구조화 출력 | JSON mode (사후 파싱) | @Generable (constrained decoding) |
| 비용 | 토큰당 과금 | 무료 |
| 모델 크기 | GPT-4o 등 | ~3B (Apple Intelligence) |
