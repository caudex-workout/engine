import type { Exercise } from "@caudex-workout/engine";

export const sampleCatalog: Exercise[] = [
  {
    id: "incline-dumbbell-press",
    name: "Incline Dumbbell Press",
    equipmentIds: ["dumbbell", "adjustable-bench"],
    movementTags: ["horizontal-push"],
    muscleContributions: [
      { muscleId: "pectoralis-major", role: "primary" },
      { muscleId: "triceps", role: "secondary" },
    ],
  },
];
