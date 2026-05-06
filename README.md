# Week 1~2: Core ML 기초

## 목표
카메라/갤러리 사진을 Core ML 모델에 넣어서 분류 결과 출력하기

## 파일 구성
```
Week1_CoreML/
├── CoreMLService.swift      ← 핵심: Core ML + Vision 파이프라인
├── ImageClassifierView.swift ← SwiftUI UI + ViewModel
└── README.md
```

## Xcode 세팅 순서

### 1. 새 프로젝트 생성
- Xcode → File → New → Project → iOS → App
- Product Name: `CoreMLBasics`
- Interface: SwiftUI

### 2. MobileNetV2 모델 다운로드
- 접속: https://developer.apple.com/machine-learning/models/
- `MobileNetV2` 검색 후 다운로드 (`.mlmodel` 파일)
- Xcode 프로젝트 네비게이터로 드래그 앤 드롭
- "Add to targets" 체크 ✓

### 3. 파일 추가
`CoreMLService.swift`, `ImageClassifierView.swift`를 프로젝트에 추가

### 4. ContentView 수정
```swift
// ContentView.swift
struct ContentView: View {
    var body: some View {
        ImageClassifierView()
    }
}
```

### 5. Info.plist에 사진 접근 권한 추가
```
NSPhotoLibraryUsageDescription = "이미지 분류를 위해 사진 접근이 필요합니다"
```

---

## 핵심 개념 정리

### Core ML vs Phase 1 LLM API

| | Phase 1 (LLM API) | Phase 2 (Core ML) |
|---|---|---|
| 실행 위치 | 서버 | 기기 (on-device) |
| 네트워크 | 필요 | 불필요 |
| 프라이버시 | 데이터 외부 전송 | 기기 밖으로 안 나감 |
| 비용 | 토큰당 과금 | 무료 |
| 속도 | 네트워크 지연 있음 | 보통 10~100ms |

### Vision + Core ML 파이프라인

```swift
// 3줄로 요약하면:
let model = try VNCoreMLModel(for: MobileNetV2().model)   // 1. 모델 래핑
let request = VNCoreMLRequest(model: model) { ... }        // 2. 요청 설정
try VNImageRequestHandler(cgImage: img).perform([request]) // 3. 실행
```

### 자주 막히는 포인트

1. **모델 파일 못 찾는 에러**
   - `MobileNetV2.mlmodel`이 프로젝트 타겟에 추가되어 있는지 확인
   - Build Phases → Copy Bundle Resources에 있어야 함

2. **UI 멈춤 현상**
   - `VNImageRequestHandler.perform()`은 메인 스레드에서 호출하면 UI 블로킹
   - `Task { }` 또는 `DispatchQueue.global().async { }` 안에서 호출

3. **이미지 방향 문제**
   - 카메라로 찍은 사진은 EXIF 방향 정보가 있음
   - `VNImageRequestHandler`에 orientation 옵션 넣어야 정확한 결과

---

## 실험해볼 것 (주간 목표)

- [ ] 여러 종류의 사진으로 테스트 — 동물, 음식, 사물
- [ ] `computeUnits`를 `.cpuOnly` vs `.all`로 바꿔서 속도 비교
- [ ] Top-1 vs Top-5 정확도 비교
- [ ] 모델 없이 `VNClassifyImageRequest`도 써보기 (Vision 내장 분류기)

---

## 다음 단계 (Week 3~4)
Vision Framework으로 QR코드/텍스트 실시간 인식 → 미니 프로젝트 핵심 기능 구현
