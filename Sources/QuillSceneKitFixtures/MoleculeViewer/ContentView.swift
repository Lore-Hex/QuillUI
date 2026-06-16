import SceneKit
import SwiftUI

struct ContentView: View {
    @State private var selection = molecules[0].id

    private var molecule: Molecule {
        molecules.first { $0.id == selection } ?? molecules[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Molecule", selection: $selection) {
                ForEach(molecules) { molecule in
                    Text(molecule.name).tag(molecule.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            SceneView(
                scene: makeMoleculeScene(molecule),
                options: [.allowsCameraControl]
            )

            Text("\(molecule.atoms.count) atoms · \(molecule.bonds.count) bonds")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(6)
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}
