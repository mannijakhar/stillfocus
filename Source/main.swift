import AppKit
import SwiftUI
import Charts
typealias FocusState<Value> = SwiftUI.State<Value>
// MARK: - Saved data

struct FocusSpan: Codable {
    var start: Date
    var end: Date

    var seconds: Double {
        max(0, end.timeIntervalSince(start))
    }
}

struct FocusSession: Codable, Identifiable {
    var id = UUID()
    var title: String
    var started: Date
    var spans: [FocusSpan] = []
    var finished: Date?

    // Optional fields preserve compatibility with the first version.
    var category: String?
    var notes: String?
    var targetSeconds: Double?

    var seconds: Double {
        spans.reduce(0) { $0 + $1.seconds }
    }

    var activity: String {
        let value = (category ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? "Unlabelled" : value
    }
}

struct FocusArchive: Codable {
    var sessions: [FocusSession] = []
    var minutes = 25
    var label = ""
    var active: UUID?

    var category: String?
    var notes: String?
}

enum ReportPeriod: String, CaseIterable {
    case day = "Day"
    case week = "Week"
}

struct ActivityTotal: Identifiable {
    var name: String
    var seconds: Double

    var id: String { name }
}

struct DayTotal: Identifiable {
    var date: Date
    var seconds: Double

    var id: Date { date }
}

// MARK: - Formatting

func durationText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))

    if total >= 3600 {
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    if total >= 60 {
        return "\(total / 60)m \(total % 60)s"
    }

    return "\(total)s"
}

func countdownText(_ seconds: Double) -> String {
    let total = max(0, Int(ceil(seconds)))

    return String(
        format: "%02d:%02d",
        total / 60,
        total % 60
    )
}

let focusAccent = Color(
    red: 0.76,
    green: 0.73,
    blue: 1.0
)

let focusBackground = Color(
    red: 0.075,
    green: 0.085,
    blue: 0.12
)

// MARK: - Application logic

@MainActor
final class FocusStore: ObservableObject {
    @Published var archive = FocusArchive()

    @Published var running = false
    @Published var compactMode = false
    @Published var windowHidden = false
    @Published var showingReports = false
    @Published var reportPeriod: ReportPeriod = .day
    @Published var reportOffset = 0

    @Published var editingSession: FocusSession?
    @Published var errorMessage: String?

    @Published var statusMessage =
        "Make a little room for focused work."

    var onDisplayChange: (() -> Void)?
    var onHideWindow: (() -> Void)?
    var onShowFloatingWindow: (() -> Void)?
    var onSummaryReady: (() -> Void)?

    private let historyURL: URL
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private var lastTick: Date?
    private var lastSave = Date.distantPast
    private var observedDay =
        Calendar.current.startOfDay(for: Date())

    private var maySave = true

    init() {
        let directory = FileManager.default
            .urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("StillFocus")

        historyURL = directory
            .appendingPathComponent("history.json")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(
                atPath: historyURL.path
            ) {
                let data = try Data(contentsOf: historyURL)

                archive = try JSONDecoder().decode(
                    FocusArchive.self,
                    from: data
                )
            }

            archive.minutes = min(
                240,
                max(1, archive.minutes)
            )

            if let activeID = archive.active,
               !archive.sessions.contains(
                    where: { $0.id == activeID }
               ) {
                archive.active = nil
            }

            if archive.active != nil {
                statusMessage =
                    "Your previous session is paused."
            }
        } catch {
            // Never overwrite a history file we could not read.
            maySave = false

            errorMessage = """
            Your saved history could not be opened.

            The existing file has not been changed:
            \(historyURL.path)

            Resolve the file problem before starting a session.
            """
        }

        timer = Timer(
            timeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }

        RunLoop.main.add(timer!, forMode: .common)

        let sleepObserver = NSWorkspace.shared
            .notificationCenter
            .addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pause()
                }
            }

        let wakeObserver = NSWorkspace.shared
            .notificationCenter
            .addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkDayChange()
                }
            }

        observers = [sleepObserver, wakeObserver]
    }

    // MARK: Current session

    var activeIndex: Int? {
        archive.sessions.firstIndex {
            $0.id == archive.active
        }
    }

    var activeSession: FocusSession? {
        guard let index = activeIndex else {
            return nil
        }

        return archive.sessions[index]
    }

    var hasActiveSession: Bool {
        activeSession != nil
    }

    var canStart: Bool {
        maySave
    }

    var elapsed: Double {
        activeSession?.seconds ?? 0
    }

    var target: Double {
        activeSession?.targetSeconds
            ?? Double(archive.minutes * 60)
    }

    var remaining: Double {
        max(0, target - elapsed)
    }

    var progress: Double {
        min(1, max(0, elapsed / max(1, target)))
    }

    var menuTitle: String {
        guard hasActiveSession else {
            return ""
        }

        return running
            ? countdownText(remaining)
            : "\(countdownText(remaining)) Ⅱ"
    }

    func toggleTimer() {
        if running {
            pause()
        } else {
            startOrResume()
        }
    }

    func startOrResume() {
        guard maySave else { return }

        if !hasActiveSession {
            let title = archive.label
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let session = FocusSession(
                title: title.isEmpty ? "Focus session" : title,
                started: Date(),
                category: archive.category,
                notes: archive.notes,
                targetSeconds: Double(archive.minutes * 60)
            )

            archive.sessions.append(session)
            archive.active = session.id
        }

        // A recovered session may already be complete.
        if remaining <= 0 {
            finish(completed: true)
            return
        }

        running = true
        lastTick = Date()
        compactMode = true

        statusMessage = "One thing at a time."
        save()
        onDisplayChange?()
        // Restore the bubble after resuming a session hidden by Pause.
        if running { onShowFloatingWindow?() }
    }

    func pause() {
        guard running else { return }

        recordTime()

        // recordTime may finish a completed session.
        guard hasActiveSession else { return }

        running = false
        lastTick = nil

        statusMessage = "Paused. Take a breath."
        save()
        onDisplayChange?()
        onHideWindow?()
    }

    func endSession() {
        if running {
            recordTime()
        }

        guard hasActiveSession else { return }
        finish(completed: false)
    }

    private func tick() {
        if running {
            recordTime()
        }

        checkDayChange()
    }

    private func recordTime() {
        guard running,
              let index = activeIndex,
              let previous = lastTick
        else {
            return
        }

        let now = Date()
        let available = remaining

        // Cap the recorded interval at the timer's target.
        let end = min(
            now,
            previous.addingTimeInterval(available)
        )

        if end > previous {
            let count = archive.sessions[index].spans.count

            if count > 0,
               abs(
                    archive.sessions[index]
                        .spans[count - 1]
                        .end
                        .timeIntervalSince(previous)
               ) < 0.001 {

                archive.sessions[index]
                    .spans[count - 1]
                    .end = end
            } else {
                archive.sessions[index].spans.append(
                    FocusSpan(
                        start: previous,
                        end: end
                    )
                )
            }
        }

        lastTick = now

        if remaining <= 0.01 {
            finish(completed: true)
        } else if now.timeIntervalSince(lastSave) >= 5 {
            save()
        }

        onDisplayChange?()
    }

    private func finish(completed: Bool) {
        guard let index = activeIndex else { return }

        archive.sessions[index].finished =
            archive.sessions[index].spans.last?.end
            ?? Date()

        let session = archive.sessions[index]

        running = false
        lastTick = nil
        archive.active = nil
        compactMode = false

        if session.seconds < 1 {
            archive.sessions.remove(at: index)
        } else {
            editingSession = session
        }

        // Keep the category for the next session,
        // but do not copy completed notes forward.
        archive.notes = ""

        statusMessage = completed
            ? "Session complete. Time for a small break."
            : "Session saved. Every focused minute counts."

        save()
        onDisplayChange?()

        if completed {
            NSSound(named: "Glass")?.play()
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    // MARK: Saving and editing

    func save() {
        guard maySave else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]

            let data = try encoder.encode(archive)

            try data.write(
                to: historyURL,
                options: .atomic
            )

            lastSave = Date()
        } catch {
            // Keep the in-memory session intact.
            running = false
            lastTick = nil

            statusMessage =
                "Saving failed. Your timer has been paused."

            if errorMessage == nil {
                errorMessage = """
                History could not be saved.

                Check available disk space and folder access.
                Your current data remains in memory.

                \(error.localizedDescription)
                """
            }

            onDisplayChange?()
        }
    }

    func updateSession(
        id: UUID,
        title: String,
        category: String,
        notes: String
    ) {
        guard let index = archive.sessions.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        archive.sessions[index].title =
            cleanTitle.isEmpty ? "Focus session" : cleanTitle

        archive.sessions[index].category =
            category.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        archive.sessions[index].notes =
            notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        save()
    }

    func shutdown() {
        pause()
        save()
    }

    // MARK: Reports

    var selectedInterval: DateInterval {
        let calendar = Calendar.current

        let component: Calendar.Component =
            reportPeriod == .day ? .day : .weekOfYear

        let date = calendar.date(
            byAdding: component,
            value: reportOffset,
            to: Date()
        )!

        return calendar.dateInterval(
            of: component,
            for: date
        )!
    }

    var todayInterval: DateInterval {
        Calendar.current.dateInterval(
            of: .day,
            for: Date()
        )!
    }

    var periodTitle: String {
        let interval = selectedInterval

        if reportPeriod == .day {
            return interval.start.formatted(
                .dateTime
                    .weekday(.abbreviated)
                    .month(.abbreviated)
                    .day()
                    .year()
            )
        }

        let lastDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: interval.end
        )!

        return """
        \(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \
        \(lastDay.formatted(.dateTime.month(.abbreviated).day().year()))
        """
    }

    func focusedSeconds(
        _ session: FocusSession,
        within interval: DateInterval
    ) -> Double {
        session.spans.reduce(0) { result, span in
            let start = max(span.start, interval.start)
            let end = min(span.end, interval.end)

            return result + max(
                0,
                end.timeIntervalSince(start)
            )
        }
    }

    func total(within interval: DateInterval) -> Double {
        archive.sessions.reduce(0) {
            $0 + focusedSeconds($1, within: interval)
        }
    }

    var reportSessions: [FocusSession] {
        archive.sessions
            .filter {
                focusedSeconds(
                    $0,
                    within: selectedInterval
                ) > 0
            }
            .sorted { $0.started > $1.started }
    }

    var activityTotals: [ActivityTotal] {
        var groups: [String: ActivityTotal] = [:]

        for session in reportSessions {
            let key = session.activity.lowercased()

            let seconds = focusedSeconds(
                session,
                within: selectedInterval
            )

            if var existing = groups[key] {
                existing.seconds += seconds
                groups[key] = existing
            } else {
                groups[key] = ActivityTotal(
                    name: session.activity,
                    seconds: seconds
                )
            }
        }

        return groups.values.sorted {
            if $0.seconds == $1.seconds {
                return $0.name < $1.name
            }

            return $0.seconds > $1.seconds
        }
    }

    var dailyTotals: [DayTotal] {
        let calendar = Calendar.current
        let interval = selectedInterval

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: offset,
                to: interval.start
            ),
            let day = calendar.dateInterval(
                of: .day,
                for: date
            ) else {
                return nil
            }

            return DayTotal(
                date: date,
                seconds: total(within: day)
            )
        }
    }

    func showCurrentReport() {
        reportOffset = 0
        showingReports = true
    }

    private func checkDayChange() {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: Date())

        guard currentDay != observedDay else {
            return
        }

        let weekChanged =
            calendar.dateInterval(
                of: .weekOfYear,
                for: observedDay
            )?.start
            != calendar.dateInterval(
                of: .weekOfYear,
                for: currentDay
            )?.start

        observedDay = currentDay
        reportPeriod = weekChanged ? .week : .day
        reportOffset = -1
        showingReports = true

        statusMessage = weekChanged
            ? "Your previous week's focus summary is ready."
            : "Your previous day's focus summary is ready."

        onSummaryReady?()
    }

    // MARK: CSV export

    private func csvCell(_ value: String) -> String {
        var safe = value

        // Prevent descriptions being treated as spreadsheet formulas.
        if let first = safe.first,
           ["=", "+", "-", "@", "\t", "\r"].contains(String(first)) {
            safe = "'" + safe
        }

        return "\"" +
            safe.replacingOccurrences(of: "\"", with: "\"\"") +
            "\""
    }

    func exportHistory() {
        if running {
            recordTime()
        }

        let panel = NSSavePanel()
        panel.title = "Export focus history"
        panel.nameFieldStringValue = "Still-Focus-History.csv"

        guard panel.runModal() == .OK,
              let destination = panel.url
        else {
            return
        }

        let formatter = ISO8601DateFormatter()

        var lines = [
            "Session,Activity,Notes,Start,End,Focused seconds"
        ]

        for session in archive.sessions {
            for span in session.spans {
                lines.append([
                    csvCell(session.title),
                    csvCell(session.activity),
                    csvCell(session.notes ?? ""),
                    csvCell(formatter.string(from: span.start)),
                    csvCell(formatter.string(from: span.end)),
                    String(Int(span.seconds))
                ].joined(separator: ","))
            }
        }

        do {
            try lines.joined(separator: "\n").write(
                to: destination,
                atomically: true,
                encoding: .utf8
            )

            statusMessage = "History exported."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Main interface

struct FocusView: View {
    @ObservedObject var store: FocusStore

    private var categoryBinding: Binding<String> {
        Binding(
            get: { store.archive.category ?? "" },
            set: { store.archive.category = $0 }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { store.archive.notes ?? "" },
            set: { store.archive.notes = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            Picker(
                "View",
                selection: $store.showingReports
            ) {
                Text("Focus").tag(false)
                Text("Your rhythm").tag(true)
            }
            .pickerStyle(.segmented)

            if store.showingReports {
                reportView
            } else {
                timerView
            }

            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 28)
        }
        .padding(24)
        .frame(width: 420, height: 720)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.14, blue: 0.21),
                    focusBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .tint(focusAccent)
        .preferredColorScheme(.dark)

    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkle")
                .foregroundStyle(focusAccent)

            Text("still")
                .font(
                    .system(
                        size: 25,
                        weight: .semibold,
                        design: .rounded
                    )
                )

            Spacer()

            if store.hasActiveSession {
                Button {
                    store.compactMode = true
                    store.onDisplayChange?()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(focusAccent)
                .help("Show floating timer")
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(
                        store.running
                            ? focusAccent
                            : Color.secondary
                    )
                    .frame(width: 6, height: 6)

                Text(store.running ? "FOCUSING" : "YOUR SPACE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timerView: some View {
        VStack(spacing: 18) {
            if let session = store.activeSession {
                VStack(spacing: 5) {
                    Text(session.activity.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(focusAccent)

                    Text(session.title)
                        .font(.headline)
                        .lineLimit(2)

                    Button("Edit session details") {
                        store.editingSession = session
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(height: 90)
            } else {
                VStack(spacing: 10) {
                    TextField(
                        "What will you work on?",
                        text: $store.archive.label
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField(
                            "Activity label, e.g. Study",
                            text: categoryBinding
                        )
                        .textFieldStyle(.roundedBorder)

                        Menu {
                            ForEach(
                                ["Work", "Study", "Reading",
                                 "Creative", "Personal"],
                                id: \.self
                            ) { category in
                                Button(category) {
                                    store.archive.category = category
                                }
                            }
                        } label: {
                            Image(systemName: "tag")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 25)
                    }

                    TextField(
                        "Optional note",
                        text: notesBinding
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            timerRing

            if !store.hasActiveSession {
                durationControls
            } else {
                Text(
                    "\(Int(store.target / 60)) minute session"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 62)
            }

            HStack(spacing: 10) {
                Button {
                    store.toggleTimer()
                } label: {
                    Label(
                        store.running
                            ? "Pause"
                            : store.hasActiveSession
                                ? "Resume focus"
                                : "Begin focus",
                        systemImage: store.running
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Color.black.opacity(0.8))
                    .background(
                        focusAccent,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!store.canStart)

                if store.hasActiveSession {
                    Button {
                        store.endSession()
                    } label: {
                        Image(systemName: "stop.fill")
                            .padding(16)
                            .background(
                                .white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("End session and save focused time")
                }
            }

            HStack {
                Label("Focused today", systemImage: "sun.max")

                Spacer()

                Text(
                    durationText(
                        store.total(
                            within: store.todayInterval
                        )
                    )
                )
                .foregroundStyle(focusAccent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(
                    .white.opacity(0.07),
                    lineWidth: 6
                )

            Circle()
                .trim(
                    from: 0,
                    to: max(0.003, 1 - store.progress)
                )
                .stroke(
                    focusAccent,
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 10) {
                Text(countdownText(store.remaining))
                    .font(
                        .system(
                            size: 54,
                            weight: .light,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(
                    store.running
                        ? "STAY WITH IT"
                        : store.hasActiveSession
                            ? "PAUSED"
                            : "READY WHEN YOU ARE"
                )
                .font(.system(size: 9, weight: .medium))
                .tracking(2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 226, height: 226)
        .padding(.vertical, 6)
    }

    private var durationControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([15, 25, 50], id: \.self) { minutes in
                    Button("\(minutes)m") {
                        store.archive.minutes = minutes
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        store.archive.minutes == minutes
                            ? focusAccent.opacity(0.22)
                            : .white.opacity(0.06),
                        in: Capsule()
                    )
                }
            }

            HStack {
                Text("Custom")

                TextField(
                    "Minutes",
                    value: $store.archive.minutes,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 55)

                Text("minutes")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: store.archive.minutes) {
            store.archive.minutes = min(
                240,
                max(1, store.archive.minutes)
            )
        }
    }

    // MARK: Report interface

    private var reportView: some View {
        VStack(spacing: 14) {
            Picker(
                "Report period",
                selection: $store.reportPeriod
            ) {
                ForEach(ReportPeriod.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    store.reportOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Previous period")

                Spacer()

                Text(store.periodTitle)
                    .font(.caption)

                Spacer()

                Button {
                    store.reportOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(store.reportOffset >= 0)
                .help("Next period")
            }

            VStack(spacing: 5) {
                Text(
                    durationText(
                        store.total(
                            within: store.selectedInterval
                        )
                    )
                )
                .font(
                    .system(
                        size: 37,
                        weight: .light,
                        design: .rounded
                    )
                )
                .foregroundStyle(focusAccent)

                Text(
                    "FOCUSED TIME · \(store.reportSessions.count) SESSIONS"
                )
                .font(.system(size: 9, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if store.reportPeriod == .week {
                        weeklyChart
                    }

                    if store.reportSessions.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "leaf")
                                .font(.title)
                                .foregroundStyle(focusAccent)

                            Text("A little focus goes a long way.")

                            Text("Your sessions will appear here.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        activityChart

                        Text("Session history")
                            .font(.headline)

                        ForEach(store.reportSessions) { session in
                            sessionCard(session)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button("Current period") {
                    store.reportOffset = 0
                }

                Spacer()

                Button("Export CSV") {
                    store.exportHistory()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(focusAccent)
        }
        .frame(maxHeight: .infinity)
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your week")
                .font(.headline)

            Chart(store.dailyTotals) { day in
                BarMark(
                    x: .value(
                        "Day",
                        day.date,
                        unit: .day
                    ),
                    y: .value(
                        "Minutes",
                        day.seconds / 60
                    )
                )
                .foregroundStyle(focusAccent)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(
                        format: .dateTime.weekday(.abbreviated)
                    )
                }
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 130)
        }
        .padding(14)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your time went")
                .font(.headline)

            Chart(store.activityTotals) { activity in
                BarMark(
                    x: .value(
                        "Minutes",
                        activity.seconds / 60
                    ),
                    y: .value(
                        "Activity",
                        activity.name
                    )
                )
                .foregroundStyle(focusAccent)
                .cornerRadius(4)
            }
            .chartYScale(
                domain: store.activityTotals.map(\.name)
            )
            .chartXAxisLabel("Focused minutes")
            .frame(
                height: CGFloat(
                    max(95, store.activityTotals.count * 34)
                )
            )

            let total = store.total(
                within: store.selectedInterval
            )

            ForEach(store.activityTotals) { activity in
                HStack {
                    Text(activity.name)

                    Spacer()

                    Text(
                        "\(durationText(activity.seconds)) · " +
                        "\(Int((activity.seconds / max(1, total)) * 100))%"
                    )
                    .foregroundStyle(focusAccent)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func sessionCard(
        _ session: FocusSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text(session.title)
                    .font(.callout.weight(.medium))

                Spacer()

                Text(
                    durationText(
                        store.focusedSeconds(
                            session,
                            within: store.selectedInterval
                        )
                    )
                )
                .font(.caption)
                .foregroundStyle(focusAccent)
            }

            Text(session.activity)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    focusAccent.opacity(0.14),
                    in: Capsule()
                )

            ForEach(
                Array(session.spans.enumerated()),
                id: \.offset
            ) { item in
                let span = item.element
                let interval = store.selectedInterval

                if span.end > interval.start &&
                    span.start < interval.end {

                    let start = max(span.start, interval.start)
                    let end = min(span.end, interval.end)

                    Text(
                        "\(start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" +
                        " – " +
                        "\(end.formatted(.dateTime.hour().minute()))"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            if let notes = session.notes,
               !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack {
                if session.id == store.archive.active {
                    Text(
                        store.running
                            ? "In progress"
                            : "Paused"
                    )
                    .font(.caption2)
                    .foregroundStyle(focusAccent)
                }

                Spacer()

                Button("Edit details") {
                    store.editingSession = session
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(focusAccent)
            }
        }
        .padding(14)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}

// MARK: - Session detail editor

struct SessionEditor: View {
    @ObservedObject var store: FocusStore
    let session: FocusSession

    @Environment(\.dismiss) private var dismiss

    @FocusState private var title: String
    @FocusState private var category: String
    @FocusState private var notes: String

    init(
        store: FocusStore,
        session: FocusSession
    ) {
        self.store = store
        self.session = session

    _title = FocusState(initialValue: session.title)
    _category = FocusState(initialValue: session.category ?? "")
    _notes = FocusState(initialValue: session.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What did you work on?")
                .font(.title2.weight(.semibold))

            Text(
                "Give this session a label and capture what you accomplished."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            TextField("Session title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField(
                "Activity label, e.g. Study",
                text: $category
            )
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(
                    ["Work", "Study", "Reading", "Personal"],
                    id: \.self
                ) { suggestion in
                    Button(suggestion) {
                        category = suggestion
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("What I did")
                .font(.headline)

            TextEditor(text: $notes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 145)
                .background(
                    .white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save details") {
                    store.updateSession(
                        id: session.id,
                        title: title,
                        category: category,
                        notes: notes
                    )

                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
        .tint(focusAccent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Compact floating timer

struct FocusWindowView: View {
    @ObservedObject var store: FocusStore

    var body: some View {
        FocusView(store: store)
        .sheet(item: Binding(
            get: { store.windowHidden ? nil : store.editingSession },
            set: { store.editingSession = $0 }
        )) { session in
            SessionEditor(
                store: store,
                session: session
            )
        }
        .alert(
            "Still Focus",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: {
                    if !$0 {
                        store.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct CompactFocusView: View {
    @ObservedObject var store: FocusStore

    private func expand() {
        store.compactMode = false
        store.onDisplayChange?()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(focusBackground)
                .overlay {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .padding(5)

            ZStack {
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.003, 1 - store.progress))
                        .stroke(focusAccent, style: StrokeStyle(
                            lineWidth: 3, lineCap: .round
                        ))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Image(systemName: store.running ? "sparkle" : "pause.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(focusAccent)
                        Text(countdownText(store.remaining))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
            }
            .allowsHitTesting(false)
        }
        .frame(width: 96, height: 96)
        .preferredColorScheme(.dark)
        .overlay {
            TimerMouseSurface(
                running: store.running,
                open: expand,
                toggle: { store.toggleTimer() },
                hide: { store.onHideWindow?() },
                finish: { store.endSession() }
            )
        }
        .overlay(alignment: .topTrailing) {
            Button {
                store.onHideWindow?()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(focusBackground, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Hide timer — focus continues in the menu bar")
            .accessibilityLabel("Hide floating timer")
        }
        .accessibilityLabel("Focus timer")
        .accessibilityValue("\(countdownText(store.remaining)) remaining")
    }
}

// Native mouse handling makes the entire bubble draggable rather than
// relying on SwiftUI's background hit testing. A click still opens details.
struct TimerMouseSurface: NSViewRepresentable {
    var running: Bool
    var open: () -> Void
    var toggle: () -> Void
    var hide: () -> Void
    var finish: () -> Void

    func makeNSView(context: Context) -> TimerMouseView {
        TimerMouseView()
    }

    func updateNSView(_ view: TimerMouseView, context: Context) {
        view.openAction = open
        view.toggleAction = toggle
        view.hideAction = hide
        view.finishAction = finish
        view.running = running
        view.toolTip = "Drag to move · Click for details · Right-click for controls"
    }
}

final class TimerMouseView: NSView {
    var openAction: (() -> Void)?
    var toggleAction: (() -> Void)?
    var hideAction: (() -> Void)?
    var finishAction: (() -> Void)?
    var running = false
    private var dragged = false
    private var mouseDownPoint = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        mouseDownPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard dragged || hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 3 else { return }
        dragged = true
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { openAction?() }
        dragged = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let actions: [(String, Selector)] = [
            (running ? "Pause focus" : "Resume focus", #selector(toggleFocus)),
            ("Open details", #selector(openDetails)),
            ("Hide timer (keep focusing)", #selector(hideTimer)),
            ("End and save session", #selector(finishSession))
        ]
        for (title, action) in actions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleFocus() { toggleAction?() }
    @objc private func openDetails() { openAction?() }
    @objc private func hideTimer() { hideAction?() }
    @objc private func finishSession() { finishAction?() }
}

final class FocusFloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Native Mac window and menu bar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = FocusStore()

    private var window: NSWindow!
    private var bubbleWindow: NSWindow!
    private var statusItem: NSStatusItem!
    private var appliedCompactMode = false

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        installApplicationMenu()
        window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 420,
                height: 720
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable
            ],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.title = "Still Focus"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        window.level = .normal
        // Remain on the assigned desktop and out of other apps' full-screen spaces.
        window.collectionBehavior = []

        window.contentView = NSHostingView(
            rootView: FocusWindowView(store: store)
        )

        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.center()

        // A separate borderless window owns the bubble. The main window's
        // title bar, standard buttons, style mask and geometry never change.
        bubbleWindow = FocusFloatingWindow(
            contentRect: NSRect(x: window.frame.minX, y: window.frame.maxY - 96, width: 96, height: 96),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        bubbleWindow.isReleasedWhenClosed = false
        bubbleWindow.level = .floating
        bubbleWindow.collectionBehavior = []
        bubbleWindow.isOpaque = false
        bubbleWindow.backgroundColor = .clear
        bubbleWindow.hasShadow = true
        bubbleWindow.contentView = NSHostingView(rootView: CompactFocusView(store: store))

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItem.button?.image = NSImage(
            systemSymbolName: "timer",
            accessibilityDescription: "Still Focus"
        )

        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()

        menu.addItem(
            withTitle: "Show Still Focus",
            action: #selector(showWindow),
            keyEquivalent: ""
        )

        menu.addItem(
            withTitle: "Show floating timer",
            action: #selector(showFloatingTimer),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Hide timer (keep focusing)",
            action: #selector(hideWindow),
            keyEquivalent: ""
        )

        menu.addItem(
            withTitle: "Start / Pause",
            action: #selector(toggleTimer),
            keyEquivalent: ""
        )

        menu.addItem(
            withTitle: "View summary",
            action: #selector(showSummary),
            keyEquivalent: ""
        )

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit Still Focus",
            action: #selector(quit),
            keyEquivalent: "q"
        )

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu

        store.onDisplayChange = { [weak self] in
            self?.refreshMenuTitle()
        }

        store.onHideWindow = { [weak self] in
            self?.hideWindow()
        }
        store.onShowFloatingWindow = { [weak self] in
            self?.showFloatingTimer()
        }
        store.onSummaryReady = { [weak self] in
            guard let self, !self.store.windowHidden else { return }
            self.showWindow()
        }

        refreshMenuTitle()
        showWindow()
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Still Focus")
        let quitItem = NSMenuItem(
            title: "Quit Still Focus", action: #selector(quit), keyEquivalent: "q"
        )
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"),
            ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let minimize = NSMenuItem(
            title: "Minimise", action: #selector(minimizeWindow), keyEquivalent: "m"
        )
        minimize.target = self
        windowMenu.addItem(minimize)
        let show = NSMenuItem(title: "Show Still Focus", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        windowMenu.addItem(show)
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private func refreshMenuTitle() {
        statusItem?.button?.title = store.menuTitle
        updateWindowSize()
    }

    private func updateWindowSize() {
        guard window != nil, bubbleWindow != nil else { return }
        let compact = store.compactMode
        guard compact != appliedCompactMode else { return }
        appliedCompactMode = compact

        if compact {
            window.orderOut(nil)
            if !store.windowHidden { bubbleWindow.orderFrontRegardless() }
        } else {
            bubbleWindow.orderOut(nil)
            if !store.windowHidden {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func minimizeWindow() {
        store.windowHidden = true
        bubbleWindow.orderOut(nil)
        store.compactMode = false
        appliedCompactMode = false
        window.miniaturize(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // This single-window focus app saves and quits when its red button
        // is clicked. Hiding without quitting is available from the menu bar.
        NSApp.terminate(nil)
        return false
    }

    func windowWillMiniaturize(_ notification: Notification) {
        store.windowHidden = true
        bubbleWindow.orderOut(nil)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        store.windowHidden = false
    }

    @objc private func hideWindow() {
        store.windowHidden = true
        window.orderOut(nil)
        bubbleWindow.orderOut(nil)
    }

    @objc private func showFloatingTimer() {
        guard store.hasActiveSession else { showWindow(); return }
        store.windowHidden = false
        store.compactMode = true
        updateWindowSize()
        window.orderOut(nil)
        bubbleWindow.orderFrontRegardless()
    }

    @objc private func showWindow() {
        store.windowHidden = false
        store.compactMode = false
        updateWindowSize()
        bubbleWindow.orderOut(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleTimer() {
        store.toggleTimer()
    }

    @objc private func showSummary() {
        store.showCurrentReport()
        showWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Finder's Open must restore our window even when the menu bar app
        // is already running with its window closed.
        if window != nil {
            showWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        // Closing the window leaves the menu bar timer running.
        false
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        store.shutdown()
    }
}

// MARK: - Start the app

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()

    application.delegate = delegate
    application.setActivationPolicy(.regular)
    // NSApplication's delegate is weak; keep the controller and all its
    // button/menu/window delegate handlers alive for the entire event loop.
    withExtendedLifetime(delegate) {
        application.run()
    }
}