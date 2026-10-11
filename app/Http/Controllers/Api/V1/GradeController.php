<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\AssignmentSubmission;
use App\Models\QuizAttempt;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class GradeController extends ApiController
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $quizGrades = QuizAttempt::where('student_id', $user->id)
            ->where('status', 'graded')
            ->whereHas('quiz', fn ($query) => $query->whereHas(
                'schoolClass',
                fn ($classQuery) => $classQuery->whereColumn(
                    'school_classes.subject_id',
                    'quizzes.subject_id',
                ),
            ))
            ->with(['quiz.schoolClass.subject', 'quiz.subject'])
            ->latest('updated_at')
            ->get()
            ->map(function (QuizAttempt $attempt) {
                $maxScore = $attempt->total_points ?? $attempt->quiz->total_points;
                $percentage = (float) $maxScore > 0
                    ? round(((float) $attempt->score / (float) $maxScore) * 100, 2)
                    : null;

                return [
                    'type' => 'quiz',
                    'id' => $attempt->id,
                    'sync_uuid' => $attempt->sync_uuid,
                    'title' => $attempt->quiz->title,
                    'subject_id' => $attempt->quiz->subject?->id,
                    'subject' => $attempt->quiz->subject?->name,
                    'class_id' => $attempt->quiz->schoolClass?->id,
                    'class' => $attempt->quiz->schoolClass?->display_name,
                    'score' => $attempt->score,
                    'max_score' => $maxScore,
                    'percentage' => $percentage,
                    'graded_at' => $attempt->updated_at,
                    'feedback' => null,
                ];
            });

        $assignmentGrades = AssignmentSubmission::where('student_id', $user->id)
            ->whereNotNull('score')
            ->whereIn('status', ['graded', 'returned'])
            ->whereHas('assignment', fn ($query) => $query->whereHas(
                'schoolClass',
                fn ($classQuery) => $classQuery->whereColumn(
                    'school_classes.subject_id',
                    'assignments.subject_id',
                ),
            ))
            ->with(['assignment.schoolClass.subject', 'assignment.subject'])
            ->latest('updated_at')
            ->get()
            ->map(fn (AssignmentSubmission $submission) => [
                'type' => 'assignment',
                'id' => $submission->id,
                'sync_uuid' => $submission->sync_uuid,
                'title' => $submission->assignment->title,
                'subject_id' => $submission->assignment->subject?->id,
                'subject' => $submission->assignment->subject?->name,
                'class_id' => $submission->assignment->schoolClass?->id,
                'class' => $submission->assignment->schoolClass?->display_name,
                'score' => $submission->score,
                'max_score' => $submission->assignment->max_score,
                'percentage' => (float) $submission->assignment->max_score > 0
                    ? round(((float) $submission->score / (float) $submission->assignment->max_score) * 100, 2)
                    : null,
                'graded_at' => $submission->updated_at,
                'feedback' => $submission->feedback,
            ]);

        $grades = $quizGrades->concat($assignmentGrades)
            ->sortByDesc('graded_at')
            ->values();

        return $this->success($grades);
    }
}
