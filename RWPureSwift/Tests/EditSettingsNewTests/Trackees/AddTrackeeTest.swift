import ComposableArchitecture
import Dao
import Testing
import DependenciesTestSupport

@testable import EditSettingsNew_Trackees

@MainActor
@Suite("AddTrackee Feature Tests", .dependency(\.uuid, .incrementing))
struct AddTrackeeTests {
    
  @Test("Set name and save trackee")
  func setAndSave() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      await store.send(.setName("Bob")){
          $0.trackee.name = "Bob"
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: "Bob"))
  }
  
  @Test("Cancel button dismisses without saving")
  func cancelButtonTapped() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      } withDependencies: {
          $0.dismiss = DismissEffect { }
      }
      
      await store.send(.cancelButtonTapped)
      // Verify no delegate actions are sent
  }
  
  @Test("Save button sends delegate action with current trackee state")
  func saveButtonSendsCurrentState() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "Initial Name")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: "Initial Name"))
  }
  
  @Test("Multiple name changes update state correctly")
  func multipleNameChanges() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      } withDependencies: {
          $0.uuid = .incrementing
      }
      
      await store.send(.setName("Alice")){
          $0.trackee.name = "Alice"
      }
      
      await store.send(.setName("Bob")){
          $0.trackee.name = "Bob"
      }
      
      await store.send(.setName("Charlie")){
          $0.trackee.name = "Charlie"
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: "Charlie"))
  }
  
  @Test("Save empty name trackee")
  func saveEmptyName() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: ""))
  }
  
  @Test("Set name with special characters")
  func setNameWithSpecialCharacters() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      let specialName = "Test 123 !@#$%^&*()"
      
      await store.send(.setName(specialName)){
          $0.trackee.name = specialName
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: specialName))
  }
  
  @Test("Set name with emoji")
  func setNameWithEmoji() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      let emojiName = "🐶 Max"
      
      await store.send(.setName(emojiName)){
          $0.trackee.name = emojiName
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: emojiName))
  }
  
  @Test("Delegate actions do not cause side effects")
  func delegateActionsNoSideEffects() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "Test")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      // Sending delegate actions directly should have no effect
      await store.send(.delegate(.saveTrackee(testTrackee)))
  }
  
  @Test("keypadAppendCharacter appends characters to build name")
  func keypadAppendCharacter() async {
      @Dependency(\.uuid) var uuid

      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")

      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }

      await store.send(.keypadAppendCharacter("B")) {
          $0.trackee.name = "B"
      }

      await store.send(.keypadAppendCharacter("o")) {
          $0.trackee.name = "Bo"
      }

      await store.send(.keypadAppendCharacter("b")) {
          $0.trackee.name = "Bob"
      }

      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: "Bob"))
  }

  @Test("keypadDeleteCharacter removes last character")
  func keypadDeleteCharacter() async {
      @Dependency(\.uuid) var uuid

      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "Bob")

      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }

      await store.send(.keypadDeleteCharacter) {
          $0.trackee.name = "Bo"
      }

      await store.send(.keypadDeleteCharacter) {
          $0.trackee.name = "B"
      }
  }

  @Test("keypadDeleteCharacter on empty name is no-op")
  func keypadDeleteCharacterEmpty() async {
      @Dependency(\.uuid) var uuid

      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")

      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }

      await store.send(.keypadDeleteCharacter)
  }

  @Test("Long name can be set and saved")
  func setLongName() async {
      @Dependency(\.uuid) var uuid
      
      let testTrackee = Trackee(id: Trackee.ID(uuid()), name: "")
      
      let store = TestStore(initialState: AddTrackeeFeature.State(trackee: testTrackee)) {
          AddTrackeeFeature()
      }
      
      let longName = String(repeating: "A", count: 1000)
      
      await store.send(.setName(longName)){
          $0.trackee.name = longName
      }
      
      await store.send(.saveButtonTapped)
      await store.receive(\.delegate.saveTrackee, Trackee(id: testTrackee.id, name: longName))
  }
}
