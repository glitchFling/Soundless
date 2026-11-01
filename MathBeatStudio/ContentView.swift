import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioController()
    @State private var project = BeatProject()
    @State private var projects: [BeatProject] = []
    @State private var showingProjects = false
    @State private var showingStepEditor = false
    @State private var message: String?
    @State private var selectedStep = 0
    @State private var saved = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    private let mint = Color(red: 0.57, green: 0.97, blue: 0.73)

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        sessionCard
                        tempoCard
                        oscillatorCard
                        sequencer(width: geometry.size.width)
                        Text("One bar. Sixteen possibilities.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.bottom, 12)
                    }
                    .frame(maxWidth: 760).padding(.horizontal, 20).padding(.top, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background {
                    LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.13), Color(red: 0.035, green: 0.045, blue: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { transport }
            .sheet(isPresented: $showingProjects) { library }
            .sheet(isPresented: $showingStepEditor) {
                ScrollView { stepEditor.padding(20) }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("MathBeat Studio", isPresented: Binding(get: { message != nil || audio.errorMessage != nil }, set: { if !$0 { message = nil; audio.errorMessage = nil } })) {
                Button("OK") { message = nil; audio.errorMessage = nil }
            } message: { Text(message ?? audio.errorMessage ?? "") }
            .onChange(of: project) { _, _ in saved = false; audio.update(project) }
            .onChange(of: scenePhase) { _, phase in if phase != .active { audio.stop() } }
        }.tint(mint).preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path").font(.title2).foregroundStyle(mint)
                .frame(width: 48, height: 48).background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("MATHBEAT").font(.caption.weight(.heavy)).tracking(3).foregroundStyle(mint)
                Text("Your pocket studio.").font(.title3.weight(.semibold))
            }
            Spacer(minLength: 0)
            Button {
                do { projects = try ProjectStore.list(); showingProjects = true }
                catch { message = error.localizedDescription }
            } label: { Image(systemName: "square.stack.3d.up").font(.title3).frame(width: 48, height: 48) }
                .buttonStyle(StudioPressStyle()).accessibilityLabel("Open projects")
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("LOCAL SESSION", systemImage: "circle.fill").foregroundStyle(mint)
                Spacer()
                Text("4/4 · 1 BAR").foregroundStyle(.secondary)
            }.font(.caption2.weight(.bold))
            TextField("Name your beat", text: $project.name).font(.title.bold())
                .submitLabel(.done).accessibilityLabel("Project name")
            HStack {
                Text("\(project.steps.compactMap { $0 }.count) notes · 16 steps").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    do { try ProjectStore.save(project); saved = true }
                    catch { message = error.localizedDescription }
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(StudioPressStyle()).sensoryFeedback(.success, trigger: saved)
            }
        }.studioCard()
    }

    private var tempoCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("TEMPO", symbol: "metronome")
                Spacer()
                Text("\(Int(project.bpm))").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                Text("BPM").font(.caption.bold()).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                tempoButton(-1, symbol: "minus")
                Slider(value: $project.bpm, in: 40...240, step: 1)
                    .accessibilityLabel("Tempo").accessibilityValue("\(Int(project.bpm)) beats per minute")
                tempoButton(1, symbol: "plus")
            }
            HStack { Text("40 · SLOW"); Spacer(); Text("FAST · 240") }
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }.studioCard()
    }

    private func tempoButton(_ change: Double, symbol: String) -> some View {
        Button { project.bpm = min(240, max(40, project.bpm + change)) } label: {
            Image(systemName: symbol).font(.headline).frame(width: 44, height: 44)
                .background(.white.opacity(0.06), in: Circle())
        }.buttonStyle(StudioPressStyle())
            .accessibilityLabel(change < 0 ? "Decrease tempo" : "Increase tempo")
            .disabled(change < 0 ? project.bpm == 40 : project.bpm == 240)
    }

    private var oscillatorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("SOUND SHAPE", symbol: "waveform")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 130 : 100), spacing: 10)], spacing: 10) {
                ForEach(Waveform.allCases) { waveform in
                    Button { project.waveform = waveform } label: {
                        VStack(spacing: 12) {
                            WaveformTrace(waveform: waveform)
                                .stroke(project.waveform == waveform ? mint : .gray, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                                .frame(height: 26).padding(.horizontal, 10)
                            Text(waveform.rawValue.capitalized).font(.caption.weight(.semibold))
                                .foregroundStyle(project.waveform == waveform ? mint : .gray)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(project.waveform == waveform ? mint.opacity(0.10) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(project.waveform == waveform ? mint.opacity(0.7) : .clear))
                    }.buttonStyle(StudioPressStyle())
                        .accessibilityLabel("\(waveform.rawValue) oscillator")
                        .accessibilityAddTraits(project.waveform == waveform ? .isSelected : [])
                }
            }
        }.studioCard()
    }

    private func sequencer(width: CGFloat) -> some View {
        let columns = typeSize.isAccessibilitySize ? 2 : (width >= 600 ? 8 : 4)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("SEQUENCER", symbol: "square.grid.3x3.fill")
                Spacer()
                Text("1/16").font(.caption.monospaced()).foregroundStyle(mint)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(0..<16, id: \.self) { step in
                    let note = project.steps[step]
                    let selected = selectedStep == step
                    Button { selectedStep = step; showingStepEditor = true } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(String(format: "%02d", step + 1)).font(.caption2.monospaced())
                                Spacer(minLength: 0)
                                Circle().fill(note == nil ? .gray.opacity(0.4) : mint).frame(width: 5, height: 5)
                            }.foregroundStyle(.secondary)
                            Text(note.map(studioNoteName) ?? "—")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(note == nil ? Color.secondary : Color.white)
                            Capsule().fill(note == nil ? .white.opacity(0.08) : mint.opacity(selected ? 1 : 0.4)).frame(height: 3)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? mint.opacity(0.15) : .white.opacity(note == nil ? 0.025 : 0.065), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? mint : .clear, lineWidth: 1.5))
                    }.buttonStyle(StudioPressStyle())
                        .accessibilityLabel("Step \(step + 1), \(note.map(studioNoteName) ?? "rest")")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Tap a step to shape its note.").font(.caption).foregroundStyle(.secondary)
        }.sensoryFeedback(.selection, trigger: selectedStep)
    }

    private var stepEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("STEP \(String(format: "%02d", selectedStep + 1))", symbol: "slider.horizontal.3")
                Spacer()
                Text(project.steps[selectedStep].map(studioNoteName) ?? "REST")
                    .font(.title3.monospaced().bold()).foregroundStyle(mint)
            }
            Toggle("Note enabled", isOn: Binding(get: { project.steps[selectedStep] != nil }, set: { project.steps[selectedStep] = $0 ? 60 : nil }))
                .font(.subheadline)
            if project.steps[selectedStep] != nil {
                Stepper(value: Binding(get: { project.steps[selectedStep] ?? 60 }, set: { project.steps[selectedStep] = $0 }), in: 48...84) {
                    Label("Pitch", systemImage: "pianokeys").font(.subheadline)
                }
                Slider(value: Binding(get: { Double(project.steps[selectedStep] ?? 60) }, set: { project.steps[selectedStep] = Int($0) }), in: 48...84, step: 1)
                    .accessibilityLabel("Step \(selectedStep + 1) pitch")
                    .accessibilityValue(studioNoteName(project.steps[selectedStep] ?? 60))
            }
        }.studioCard()
    }

    private var transport: some View {
        VStack(spacing: 10) {
            Button {
                if audio.isPlaying || audio.isPreparing { audio.stop() } else { audio.play(project) }
            } label: {
                HStack(spacing: 12) {
                    if audio.isPreparing { ProgressView().tint(.black) }
                    else { Image(systemName: audio.isPlaying ? "stop.fill" : "play.fill") }
                    Text(audio.isPreparing ? "Cancel loading" : (audio.isPlaying ? "Stop loop" : "Play loop"))
                    Spacer()
                    Image(systemName: "repeat").opacity(0.6)
                }
                .font(.headline).foregroundStyle(.black).padding(.horizontal, 22)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(mint, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(StudioPressStyle())
            Text(audio.isPlaying ? "LOOPING · EDITS JOIN AT A LOOP BOUNDARY" : "READY WHEN YOU ARE")
                .font(.caption2.weight(.medium)).tracking(1).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 760).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
        .frame(maxWidth: .infinity).background(.ultraThinMaterial)
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
    }

    private var library: some View {
        NavigationStack {
            List {
                Button {
                    audio.stop(); project = BeatProject(); selectedStep = 0; showingProjects = false
                } label: { Label("New session", systemImage: "plus.circle.fill").frame(minHeight: 44) }
                if projects.isEmpty {
                    ContentUnavailableView("Your next beat starts here", systemImage: "waveform", description: Text("Save a session to keep it in your library."))
                        .listRowBackground(Color.clear)
                }
                ForEach(projects) { savedProject in
                    Button {
                        audio.stop(); project = savedProject; selectedStep = 0; showingProjects = false
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "waveform").foregroundStyle(mint)
                                .frame(width: 42, height: 42).background(mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(savedProject.name).font(.headline).foregroundStyle(.primary)
                                Text("\(Int(savedProject.bpm)) BPM · \(savedProject.waveform.rawValue.capitalized)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                }.onDelete { indices in
                    do {
                        for index in indices { try ProjectStore.delete(projects[index]) }
                        projects = try ProjectStore.list()
                    } catch { showingProjects = false; message = error.localizedDescription }
                }
            }.navigationTitle("Your sessions")
                .toolbar { Button("Done") { showingProjects = false } }
        }.tint(mint)
    }
}
