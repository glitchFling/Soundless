import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioController()
    @State private var project = BeatProject()
    @State private var projects: [BeatProject] = []
    @State private var showingProjects = false
    @State private var message: String?
    @Environment(\.scenePhase) private var scenePhase

    private func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make numbers sing.").font(.title2.bold())
                    TextField("Project name", text: $project.name).textFieldStyle(.roundedBorder)
                    HStack {
                        Text("TEMPO").font(.caption.bold())
                        Spacer()
                        Text("\(Int(project.bpm)) BPM").monospacedDigit()
                    }
                    Slider(value: $project.bpm, in: 40...240, step: 1).accessibilityLabel("Tempo")
                    Picker("Oscillator", selection: $project.waveform) {
                        ForEach(Waveform.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("16 STEPS · ONE BAR · 4/4").font(.caption.bold()).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(0..<16, id: \.self) { step in
                            VStack(spacing: 8) {
                                Text(String(format: "%02d", step + 1)).font(.caption.monospaced().bold())
                                Picker("Step \(step + 1)", selection: $project.steps[step]) {
                                    Text("Rest").tag(Int?.none)
                                    ForEach(48...84, id: \.self) { pitch in
                                        Text(noteName(pitch)).tag(Optional(pitch))
                                    }
                                }.labelsHidden().tint(project.steps[step] == nil ? .secondary : .cyan)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(project.steps[step] == nil ? Color.gray.opacity(0.12) : Color.cyan.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityElement(children: .contain)
                        }
                    }
                    Button {
                        if audio.isPlaying { audio.stop() } else { audio.play(project) }
                    } label: {
                        Label(audio.isPlaying ? "Stop" : "Play Loop", systemImage: audio.isPlaying ? "stop.fill" : "play.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(10)
                    }.buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                    Text("Each step is a sixteenth note. Edits join playback at an upcoming loop boundary.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("MathBeat Studio")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Save", systemImage: "square.and.arrow.down") {
                        do { try ProjectStore.save(project); message = "Project saved." }
                        catch { message = error.localizedDescription }
                    }
                    Button("Projects", systemImage: "folder") {
                        do { projects = try ProjectStore.list(); showingProjects = true }
                        catch { message = "Could not load projects: \(error.localizedDescription)" }
                    }
                }
            }
            .sheet(isPresented: $showingProjects) {
                NavigationStack {
                    List {
                        Button("New Project") { audio.stop(); project = BeatProject(); showingProjects = false }
                        ForEach(projects) { saved in
                            Button(saved.name) { audio.stop(); project = saved; showingProjects = false }
                        }.onDelete { indices in
                            do {
                                for index in indices { try ProjectStore.delete(projects[index]) }
                                projects = try ProjectStore.list()
                            } catch { message = error.localizedDescription }
                        }
                    }
                    .navigationTitle("Local Projects")
                    .toolbar { Button("Done") { showingProjects = false } }
                }
            }
            .alert("MathBeat Studio", isPresented: Binding(get: { message != nil || audio.errorMessage != nil },
                                                         set: { if !$0 { message = nil; audio.errorMessage = nil } })) {
                Button("OK") { message = nil; audio.errorMessage = nil }
            } message: { Text(message ?? audio.errorMessage ?? "") }
            .onChange(of: project.bpm) { _, _ in audio.update(project) }
            .onChange(of: project.waveform) { _, _ in audio.update(project) }
            .onChange(of: project.steps) { _, _ in audio.update(project) }
            .onChange(of: scenePhase) { _, phase in if phase != .active { audio.stop() } }
        }.preferredColorScheme(.dark)
    }
}
