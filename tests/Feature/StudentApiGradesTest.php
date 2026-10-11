<?php

namespace Tests\Feature;

use App\Models\AcademicYear;
use App\Models\Assignment;
use App\Models\AssignmentSubmission;
use App\Models\Quiz;
use App\Models\QuizAttempt;
use App\Models\SchoolClass;
use App\Models\Subject;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class StudentApiGradesTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_student_receives_their_quiz_and_assignment_grades_by_subject(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $teacher = User::where('email', 'teacher@edusync.test')->firstOrFail();
        $mathClass = $teacher->taughtClasses()->firstOrFail();
        $mathQuiz = Quiz::where('title', 'Mathematics Quiz #1')->firstOrFail();
        $mathAssignment = Assignment::where('title', 'Algebra Problem Set')->firstOrFail();

        $science = Subject::create([
            'code' => 'SCI7',
            'name' => 'Science 7',
            'description' => 'Science',
            'grade_level' => 'Grade 7',
            'teacher_id' => $teacher->id,
            'academic_year_id' => AcademicYear::firstOrFail()->id,
            'status' => 'active',
        ]);
        $scienceClass = SchoolClass::create([
            'name' => 'Grade 7',
            'section' => 'B',
            'grade_level' => 'Grade 7',
            'subject_id' => $science->id,
            'teacher_id' => $teacher->id,
            'academic_year_id' => $science->academic_year_id,
            'status' => 'active',
        ]);
        $scienceClass->students()->attach($student->id, [
            'enrolled_at' => now(),
            'status' => 'enrolled',
        ]);

        $scienceQuiz = $this->createQuiz($teacher, $science, $scienceClass, 'Science Quiz', 10);
        $scienceAssignment = $this->createAssignment(
            $teacher,
            $science,
            $scienceClass,
            'Science Report',
            10,
        );
        $mathAttempt = $this->createQuizAttempt($student, $mathQuiz, 3, 4);
        $scienceAttempt = $this->createQuizAttempt($student, $scienceQuiz, 8, 10);
        $this->createAssignmentSubmission($student, $mathAssignment, 75);
        $scienceSubmission = $this->createAssignmentSubmission($student, $scienceAssignment, 7);
        $scienceSubmission->update(['feedback' => 'Clear explanation.']);
        $misfiledQuiz = $this->createQuiz(
            $teacher,
            $science,
            $mathClass,
            'Misfiled Science Quiz',
            10,
        );
        $misfiledAttempt = $this->createQuizAttempt($student, $misfiledQuiz, 9, 10);

        $otherStudent = User::factory()->student()->create();
        $otherStudentAttempt = $this->createQuizAttempt($otherStudent, $mathQuiz, 4, 4);

        $token = $student->createToken('grades-test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/v1/grades')->assertOk();

        $grades = collect($response->json('data'));
        $this->assertCount(4, $grades);
        $this->assertFalse($grades->contains('id', $otherStudentAttempt->id));
        $this->assertFalse($grades->contains('id', $misfiledAttempt->id));

        $mathGrade = $grades->firstWhere('id', $mathAttempt->id);
        $this->assertSame('quiz', $mathGrade['type']);
        $this->assertSame('Mathematics 7', $mathGrade['subject']);
        $this->assertSame($mathClass->display_name, $mathGrade['class']);
        $this->assertSame(3, (int) $mathGrade['score']);
        $this->assertSame(4, (int) $mathGrade['max_score']);
        $this->assertEquals(75, $mathGrade['percentage']);
        $this->assertNotEmpty($mathGrade['graded_at']);

        $scienceGrade = $grades->firstWhere('id', $scienceAttempt->id);
        $this->assertSame('Science 7', $scienceGrade['subject']);
        $this->assertEquals(80, $scienceGrade['percentage']);

        $assignmentGrade = $grades->first(
            fn (array $grade) => $grade['type'] === 'assignment'
                && $grade['id'] === $scienceSubmission->id,
        );
        $this->assertSame('assignment', $assignmentGrade['type']);
        $this->assertSame('Science Report', $assignmentGrade['title']);
        $this->assertSame('Science 7', $assignmentGrade['subject']);
        $this->assertSame(10, (int) $assignmentGrade['max_score']);
        $this->assertEquals(70, $assignmentGrade['percentage']);
        $this->assertSame('Clear explanation.', $assignmentGrade['feedback']);
    }

    public function test_quiz_grade_is_available_after_authenticated_synchronization(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = Quiz::with('questions.options')->firstOrFail();
        $token = $student->createToken('grades-sync-test')->plainTextToken;
        $now = now()->toIso8601String();

        $this->withToken($token)
            ->postJson('/api/v1/submissions/quiz', [
                'quiz_id' => $quiz->id,
                'sync_uuid' => (string) Str::uuid(),
                'started_at' => $now,
                'submitted_at' => $now,
                'answers' => $quiz->questions->map(fn ($question) => [
                    'question_id' => $question->id,
                    'selected_options' => $question->options
                        ->where('is_correct', true)
                        ->pluck('id')
                        ->values()
                        ->all(),
                    'answer_text' => $question->type->value === 'identification'
                        ? '56'
                        : null,
                ])->all(),
            ])
            ->assertCreated();

        $this->withToken($token)
            ->getJson('/api/v1/grades')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.type', 'quiz')
            ->assertJsonPath('data.0.title', $quiz->title)
            ->assertJsonPath('data.0.subject', $quiz->subject->name)
            ->assertJsonPath('data.0.percentage', 100);
    }

    public function test_student_without_grades_receives_an_empty_list(): void
    {
        $student = User::factory()->student()->create();
        $token = $student->createToken('grades-test')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/v1/grades')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonCount(0, 'data');
    }

    private function createQuiz(
        User $teacher,
        Subject $subject,
        SchoolClass $schoolClass,
        string $title,
        float $total,
    ): Quiz {
        return Quiz::create([
            'title' => $title,
            'subject_id' => $subject->id,
            'school_class_id' => $schoolClass->id,
            'teacher_id' => $teacher->id,
            'duration_minutes' => 30,
            'max_attempts' => 1,
            'passing_score' => 60,
            'total_points' => $total,
            'status' => 'published',
        ]);
    }

    private function createAssignment(
        User $teacher,
        Subject $subject,
        SchoolClass $schoolClass,
        string $title,
        float $total,
    ): Assignment {
        return Assignment::create([
            'title' => $title,
            'subject_id' => $subject->id,
            'school_class_id' => $schoolClass->id,
            'teacher_id' => $teacher->id,
            'max_score' => $total,
            'status' => 'published',
        ]);
    }

    private function createQuizAttempt(
        User $student,
        Quiz $quiz,
        float $score,
        float $total,
    ): QuizAttempt {
        return QuizAttempt::create([
            'quiz_id' => $quiz->id,
            'student_id' => $student->id,
            'sync_uuid' => (string) Str::uuid(),
            'started_at' => now()->subHour(),
            'submitted_at' => now(),
            'score' => $score,
            'percentage' => $score / $total * 100,
            'total_points' => $total,
            'status' => 'graded',
        ]);
    }

    private function createAssignmentSubmission(
        User $student,
        Assignment $assignment,
        float $score,
    ): AssignmentSubmission {
        return AssignmentSubmission::create([
            'assignment_id' => $assignment->id,
            'student_id' => $student->id,
            'sync_uuid' => (string) Str::uuid(),
            'submitted_at' => now(),
            'score' => $score,
            'status' => 'graded',
        ]);
    }
}
