import AppModel
import EventKit
import PhotosUI
import SwiftUI
import DataModel
import Utility

public struct CheckPermissionsView: View {
    @State var calenderStatus: EKAuthorizationStatus
    @State var photoStatus: PHAuthorizationStatus
    
    @Binding var state: AppState
    
    public init(state: Binding<AppState>) {
        self.calenderStatus = EKEventStore.authorizationStatus(for: .event)
        self.photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self._state = state
    }
    
    private func openPhotoSettings(){
        #if targetEnvironment(macCatalyst)
        Task.detached { @MainActor in
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
            UIApplication.shared.open(URL(string: url)!)
        }
        #else
        Task.detached { @MainActor in
            let url = UIApplication.openSettingsURLString
            UIApplication.shared.open(URL(string: url)!)
        }
        #endif
    }

    private func openCalendarSettings(){
        #if targetEnvironment(macCatalyst)
        Task.detached { @MainActor in
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            UIApplication.shared.open(URL(string: url)!)
        }
        #else
        Task.detached { @MainActor in
            let url = UIApplication.openSettingsURLString
            UIApplication.shared.open(URL(string: url)!)
        }
        #endif
    }
    
    public var body: some View {
        Form {
            Section {
                Text("This application makes heavy use of the Apple provided calendar and photo library resources and will not operate without them.")
            }
            
            Section {
                if calenderStatus == .denied {
                    Text("In order to use this application you will need to allow full calendar access in the Settings App.")
                    Button("Open Settings Application"){
                        openCalendarSettings()
                    }
                } else if calenderStatus == .restricted {
                    Text("In order to use this application you will need to allow full calendar access from Screen Time.")
                    Button("Open Settings Application"){
                        openCalendarSettings()
                    }
                } else if calenderStatus != .fullAccess {
                    Button("Authorize Calendar Access"){
                        Task.detached(operation: {
                            _ = try await GlobalEventStore.shared
                                .requestAccess()
                        })
                    }
                } else {
                    Text("Calendar Access Granted")
                }
            }
            
            Section {
                if photoStatus == .denied {
                    Text("In order to use this application you will need to allow full photo access in the Settings App.")
                    Button("Open Settings Application"){
                        openPhotoSettings()
                    }
                } else if photoStatus == .restricted {
                    Text("In order to use this application you will need to allow full photo access from Screen Time.")
                    Button("Open Settings Application"){
                        openPhotoSettings()
                    }
                } else if photoStatus != .authorized {
                    Button("Authorize Photo Access"){
                        Task.detached(operation: {
                            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        })
                    }
                } else {
                    Text("Photo Access Granted")
                }
            }
        }.task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(1 * Double(NSEC_PER_SEC)))
                withAnimation {
                    calenderStatus = EKEventStore.authorizationStatus(for: .event)
                    photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    
                    if calenderStatus == .fullAccess && photoStatus == .authorized {
                        state = .editSettings
                    }
                }
            }
        }
    }
}

#Preview {
    @State var state = AppState.checkPermissions
    return CheckPermissionsView(state: $state)
}
