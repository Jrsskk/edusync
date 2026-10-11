<?php

namespace Tests\Feature;

use App\Models\User;
use App\Enums\UserRole;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class SyncTest extends TestCase
{
    use RefreshDatabase;

    public function test_browser_session_can_authenticate_first_party_sync_requests(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();

        $this->post('/login', [
            'email' => $student->email,
            'password' => 'password',
        ])->assertRedirect();

        $this->withHeader('Origin', config('app.url'))
            ->getJson('/api/v1/sync/status')
            ->assertOk()
            ->assertJsonPath('success', true);
    }

    public function test_student_sync_page_offers_local_failed_queue_management(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();

        $this->actingAs($student)
            ->get(route('student.sync.index'))
            ->assertOk()
            ->assertSee('Delete selected failed')
            ->assertSee('deleteFailedQueueItem')
            ->assertSee('deleteFailedQueueItems')
            ->assertSee('The submitted data will not be deleted.');
    }

    public function test_duplicate_sync_uuid_is_idempotent(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->first();
        $quiz = \App\Models\Quiz::first();
        $uuid = Str::uuid()->toString();

        $payload = [
            'sync_uuid' => $uuid,
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => [
                'quiz_id' => $quiz->id,
                'attempt_number' => 1,
                'started_at' => now()->toIso8601String(),
                'completed_at' => now()->toIso8601String(),
                'submitted_at' => now()->toIso8601String(),
                'answers' => $quiz->questions->map(fn ($q) => [
                    'question_id' => $q->id,
                    'selected_options' => $q->options->where('is_correct', true)->pluck('id')->values()->all(),
                    'answer_text' => $q->type->value === 'identification' ? '56' : null,
                ])->all(),
            ],
            'device_id' => 'test-device',
        ];

        $token = $student->createToken('test')->plainTextToken;

        $this->withToken($token)->postJson('/api/v1/sync', $payload)
            ->assertOk()
            ->assertJsonPath('data.sync_uuid', $uuid)
            ->assertJsonPath('data.status', 'synced');
        $this->withToken($token)->postJson('/api/v1/sync', $payload)->assertOk();

        $this->assertEquals(1, \App\Models\QuizAttempt::where('sync_uuid', $uuid)->count());
        $this->assertDatabaseHas('quiz_attempts', [
            'sync_uuid' => $uuid,
            'student_id' => $student->id,
            'quiz_id' => $quiz->id,
        ]);
    }

    public function test_sync_uuid_cannot_be_reused_for_a_different_quiz_payload(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::with('questions.options')->firstOrFail();
        $token = $student->createToken('test')->plainTextToken;
        $uuid = Str::uuid()->toString();
        $now = now()->toIso8601String();
        $payload = [
            'quiz_id' => $quiz->id,
            'attempt_number' => 1,
            'started_at' => $now,
            'completed_at' => $now,
            'submitted_at' => $now,
            'answers' => $quiz->questions->map(fn ($question) => [
                'question_id' => $question->id,
                'selected_options' => $question->options->where('is_correct', true)->pluck('id')->values()->all(),
            ])->all(),
        ];

        $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => $uuid,
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => $payload,
        ])->assertOk();

        $payload['answers'][0]['answer_text'] = 'changed payload';
        $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => $uuid,
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => $payload,
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('sync_uuid');

        $this->assertDatabaseCount('quiz_attempts', 1);
    }

    public function test_quiz_attempt_with_all_questions_unanswered_can_sync(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::firstOrFail();
        $token = $student->createToken('test')->plainTextToken;
        $now = now()->toIso8601String();

        $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => Str::uuid()->toString(),
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => [
                'quiz_id' => $quiz->id,
                'attempt_number' => 1,
                'started_at' => $now,
                'completed_at' => $now,
                'submitted_at' => $now,
                'answers' => [],
            ],
        ])->assertOk()
            ->assertJsonPath('success', true);
    }

    public function test_offline_assignment_submission_accepts_an_empty_local_file_path(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $assignment = \App\Models\Assignment::firstOrFail();
        $token = $student->createToken('test')->plainTextToken;
        $uuid = Str::uuid()->toString();

        $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => $uuid,
            'entity_type' => 'assignment_submission',
            'action' => 'create',
            'payload' => [
                'assignment_id' => $assignment->id,
                'text_response' => 'Completed offline.',
                'file_path' => null,
                'status' => 'submitted',
                'version' => 1,
                'submitted_at' => now()->toIso8601String(),
            ],
        ])->assertOk()
            ->assertJsonPath('success', true);

        $this->assertDatabaseHas('assignment_submissions', [
            'sync_uuid' => $uuid,
            'assignment_id' => $assignment->id,
            'student_id' => $student->id,
            'text_response' => 'Completed offline.',
        ]);
    }

    public function test_offline_sync_finalizes_the_assignment_draft_created_by_the_browser(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $assignment = \App\Models\Assignment::firstOrFail();
        $uuid = Str::uuid()->toString();
        \App\Models\AssignmentSubmission::create([
            'assignment_id' => $assignment->id,
            'student_id' => $student->id,
            'sync_uuid' => $uuid,
            'status' => 'not_started',
            'version' => 1,
        ]);
        $token = $student->createToken('test')->plainTextToken;
        $submittedAt = now()->toIso8601String();

        $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => $uuid,
            'entity_type' => 'assignment_submission',
            'action' => 'create',
            'payload' => [
                'assignment_id' => $assignment->id,
                'text_response' => 'Prepared without a connection.',
                'status' => 'submitted',
                'version' => 2,
                'submitted_at' => $submittedAt,
            ],
        ])->assertOk()
            ->assertJsonPath('success', true);

        $this->assertDatabaseHas('assignment_submissions', [
            'sync_uuid' => $uuid,
            'student_id' => $student->id,
            'status' => 'submitted',
            'text_response' => 'Prepared without a connection.',
            'version' => 2,
        ]);
        $this->assertNotNull(\App\Models\AssignmentSubmission::where('sync_uuid', $uuid)->value('submitted_at'));
    }

    public function test_offline_assignment_file_sync_updates_the_existing_submission_record(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $assignment = \App\Models\Assignment::firstOrFail();
        $uuid = Str::uuid()->toString();
        \App\Models\AssignmentSubmission::create([
            'assignment_id' => $assignment->id,
            'student_id' => $student->id,
            'sync_uuid' => $uuid,
            'status' => 'not_started',
            'version' => 1,
        ]);
        $this->mock(\App\Services\AssignmentService::class, function ($mock): void {
            $mock->shouldReceive('storeSubmissionFile')
                ->once()
                ->andReturn([
                    'path' => 'submissions/offline-work.pdf',
                    'name' => 'offline-work.pdf',
                    'mime_type' => 'application/pdf',
                    'size' => 1024,
                ]);
        });
        $token = $student->createToken('test')->plainTextToken;

        $this->withToken($token)->post('/api/v1/submissions/assignment', [
            'assignment_id' => $assignment->id,
            'sync_uuid' => $uuid,
            'text_response' => 'Prepared with an attachment.',
            'status' => 'submitted',
            'version' => 2,
            'submitted_at' => now()->toIso8601String(),
            'file' => \Illuminate\Http\UploadedFile::fake()->create('offline-work.pdf', 1, 'application/pdf'),
        ])->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.submission.file_name', 'offline-work.pdf');

        $this->assertDatabaseHas('assignment_submissions', [
            'sync_uuid' => $uuid,
            'status' => 'submitted',
            'text_response' => 'Prepared with an attachment.',
            'file_path' => 'submissions/offline-work.pdf',
            'file_name' => 'offline-work.pdf',
            'version' => 2,
        ]);
    }

    public function test_sync_now_recovers_a_stale_syncing_quiz_attempt(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::with('questions.options')->firstOrFail();
        $uuid = Str::uuid()->toString();
        $now = now()->toIso8601String();
        $queueItem = \App\Models\SyncQueue::create([
            'user_id' => $student->id,
            'sync_uuid' => $uuid,
            'entity_type' => 'quiz_attempt',
            'entity_id' => $quiz->id,
            'action' => 'create',
            'payload' => [
                'quiz_id' => $quiz->id,
                'attempt_number' => 1,
                'started_at' => $now,
                'completed_at' => $now,
                'submitted_at' => $now,
                'answers' => $quiz->questions->map(fn ($question) => [
                    'question_id' => $question->id,
                    'selected_options' => $question->options->where('is_correct', true)->pluck('id')->values()->all(),
                ])->all(),
            ],
            'status' => 'syncing',
        ]);
        \App\Models\SyncQueue::whereKey($queueItem->id)
            ->update(['updated_at' => now()->subMinutes(10)]);

        $token = $student->createToken('test')->plainTextToken;
        $this->withToken($token)->postJson('/api/v1/sync/now')
            ->assertOk()
            ->assertJsonPath('data.processed', 1);

        $this->assertDatabaseHas('sync_queue', [
            'id' => $queueItem->id,
            'status' => 'synced',
        ]);
        $this->assertDatabaseHas('quiz_attempts', ['sync_uuid' => $uuid]);
    }

    public function test_student_sync_status_reports_queue_counts_and_last_success(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::firstOrFail();
        $syncedAt = now()->subMinute();

        foreach ([
            ['synced', $syncedAt],
            ['pending', null],
            ['failed', null],
        ] as [$status, $itemSyncedAt]) {
            \App\Models\SyncQueue::create([
                'user_id' => $student->id,
                'sync_uuid' => Str::uuid(),
                'entity_type' => 'quiz_attempt',
                'entity_id' => $quiz->id,
                'action' => 'create',
                'payload' => ['quiz_id' => $quiz->id],
                'status' => $status,
                'synced_at' => $itemSyncedAt,
            ]);
        }

        $token = $student->createToken('test')->plainTextToken;
        $response = $this->withToken($token)->getJson('/api/v1/sync/status')
            ->assertOk()
            ->assertJsonPath('data.pending', 1)
            ->assertJsonPath('data.syncing', 0)
            ->assertJsonPath('data.synced', 1)
            ->assertJsonPath('data.failed', 1);
        $this->assertNotNull($response->json('data.last_synced_at'));
    }

    public function test_sync_rejects_unrecognized_answer_fields_before_saving(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::with('questions')->firstOrFail();
        $token = $student->createToken('test')->plainTextToken;

        $response = $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => Str::uuid()->toString(),
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => [
                'quiz_id' => $quiz->id,
                'answers' => [[
                    'question_id' => $quiz->questions->first()->id,
                    'is_correct' => true,
                ]],
            ],
        ])->assertUnprocessable();

        $this->assertDatabaseCount('quiz_attempts', 0);
    }

    public function test_failed_quiz_sync_returns_the_server_rejection_reason(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::with('questions')->firstOrFail();
        $token = $student->createToken('test')->plainTextToken;
        $now = now()->toIso8601String();

        $response = $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => Str::uuid()->toString(),
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => [
                'quiz_id' => $quiz->id,
                'attempt_number' => 99,
                'started_at' => $now,
                'completed_at' => $now,
                'submitted_at' => $now,
                'answers' => [[
                    'question_id' => $quiz->questions->first()->id,
                ]],
            ],
        ]);
        $response->assertUnprocessable()
            ->assertJsonPath('success', false)
            ->assertJsonPath('message', 'Invalid quiz attempt number.')
            ->assertJsonPath('data.status', 'failed');
    }

    public function test_quiz_attempt_started_before_scheduled_start_can_sync(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::firstOrFail();
        $quiz->update(['starts_at' => now()->addDay()]);
        $token = $student->createToken('test')->plainTextToken;
        $startedAt = now()->subMinute();
        $submittedAt = now();

        $this->withToken($token)->postJson('/api/v1/sync', [
            'sync_uuid' => Str::uuid()->toString(),
            'entity_type' => 'quiz_attempt',
            'action' => 'create',
            'payload' => [
                'quiz_id' => $quiz->id,
                'attempt_number' => 1,
                'started_at' => $startedAt->toIso8601String(),
                'completed_at' => $submittedAt->toIso8601String(),
                'submitted_at' => $submittedAt->toIso8601String(),
                'answers' => [],
            ],
        ])->assertOk()
            ->assertJsonPath('success', true);

        $this->assertDatabaseHas('quiz_attempts', [
            'quiz_id' => $quiz->id,
            'student_id' => $student->id,
            'started_at' => $startedAt->toDateTimeString(),
        ]);
    }

    public function test_assignment_download_provides_an_authorized_attachment_endpoint(): void
    {
        Storage::fake('public');
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $assignment = \App\Models\Assignment::firstOrFail();
        Storage::disk('public')->put('assignments/offline-handout.pdf', 'handout');
        $assignment->update([
            'attachment_path' => 'assignments/offline-handout.pdf',
            'attachment_file_name' => 'offline-handout.pdf',
            'attachment_file_type' => 'application/pdf',
        ]);
        $token = $student->createToken('test')->plainTextToken;

        $download = $this->withToken($token)
            ->getJson("/api/v1/assignments/{$assignment->id}/download")
            ->assertOk();
        $attachmentUrl = $download->json('data.attachment_url');
        $this->assertSame(
            route('api.v1.assignments.attachment', $assignment),
            $attachmentUrl,
        );

        $this->withToken($token)->get($attachmentUrl)
            ->assertOk()
            ->assertHeader('Content-Type', 'application/pdf')
            ->assertDownload('offline-handout.pdf');
    }

    public function test_offline_quiz_page_waits_for_offline_module_before_starting(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->firstOrFail();
        $quiz = \App\Models\Quiz::firstOrFail();

        $this->actingAs($student)
            ->get(route('student.quizzes.offline', $quiz))
            ->assertOk()
            ->assertSee('EduSyncOfflineReady')
            ->assertSee('edusync:offline-ready')
            ->assertSee('Preparing offline quiz...');
    }

    public function test_student_pull_returns_teacher_changes_and_new_grades(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->first();
        $class = $student->enrolledClasses()->first();
        $quiz = \App\Models\Quiz::first();
        $assignment = \App\Models\Assignment::first();
        $token = $student->createToken('test')->plainTextToken;

        $initial = $this->withToken($token)->getJson('/api/v1/sync')->assertOk();
        $since = $initial->json('data.synced_at');

        $this->travel(2)->seconds();
        $quiz->update(['title' => 'Edited quiz title']);
        $assignment->update(['deadline' => now()->addDays(20)]);
        $draftQuiz = $quiz->replicate();
        $draftQuiz->title = 'Draft quiz';
        $draftQuiz->status = 'draft';
        $draftQuiz->save();
        $draftQuiz->update(['status' => 'published']);
        $draftAssignment = $assignment->replicate();
        $draftAssignment->title = 'Draft assignment';
        $draftAssignment->status = 'draft';
        $draftAssignment->save();
        $draftAssignment->update(['status' => 'published']);
        \App\Models\Announcement::create([
            'title' => 'New announcement', 'message' => 'Read this update.',
            'target_audience' => 'students', 'published_at' => now(), 'created_by' => $quiz->teacher_id,
        ]);
        \App\Models\AssignmentSubmission::create([
            'assignment_id' => $assignment->id, 'student_id' => $student->id,
            'sync_uuid' => Str::uuid(), 'status' => 'graded', 'score' => 88,
            'feedback' => 'Good work.', 'submitted_at' => now(), 'version' => 1,
        ]);

        $response = $this->withToken($token)->getJson('/api/v1/sync?since='.urlencode($since))->assertOk();
        $response->assertJsonPath('data.quizzes.0.title', 'Edited quiz title');
        $this->assertContains($draftQuiz->id, collect($response->json('data.quizzes'))->pluck('id')->all());
        $this->assertContains($draftAssignment->id, collect($response->json('data.assignments'))->pluck('id')->all());
        $this->assertContains('New announcement', collect($response->json('data.announcements'))->pluck('title')->all());
        $this->assertContains(88, collect($response->json('data.grades'))->pluck('score')->all());

        $nextSince = $response->json('data.synced_at');
        $this->travel(2)->seconds();
        $quiz->update(['title' => 'Edited quiz title again']);

        $nextResponse = $this->withToken($token)
            ->getJson('/api/v1/sync?since='.urlencode($nextSince))
            ->assertOk();
        $this->assertSame(
            'Edited quiz title again',
            collect($nextResponse->json('data.quizzes'))->firstWhere('id', $quiz->id)['title'],
        );
    }

    public function test_new_teacher_content_is_immediately_visible_to_students(): void
    {
        $this->seed(\Database\Seeders\EduSyncSeeder::class);
        $student = User::where('email', 'student@edusync.test')->first();
        $teacher = User::where('email', 'teacher@edusync.test')->first();
        $class = $student->enrolledClasses()->first();
        $token = $student->createToken('test')->plainTextToken;

        $quiz = app(\App\Services\QuizService::class)->create([
            'title' => 'New student quiz',
            'instructions' => 'Answer this question.',
            'subject_id' => $class->subject_id,
            'school_class_id' => $class->id,
            'starts_at' => now(),
            'deadline' => now()->addDay(),
            'duration_minutes' => 15,
            'max_attempts' => 1,
            'passing_score' => 60,
            'status' => 'published',
            'questions' => [
                [
                    'type' => 'multiple_choice',
                    'question_text' => 'Which number is 2 + 2?',
                    'points' => 1,
                    'order' => 1,
                    'options' => [
                        ['option_text' => '3', 'is_correct' => false, 'order' => 1],
                        ['option_text' => '4', 'is_correct' => true, 'order' => 2],
                    ],
                ],
            ],
        ], $teacher);

        $assignment = app(\App\Services\AssignmentService::class)->create($teacher, [
            'title' => 'New student assignment',
            'description' => 'Read the chapter.',
            'instructions' => 'Submit your summary.',
            'subject_id' => $class->subject_id,
            'school_class_id' => $class->id,
            'deadline' => now()->addDay(),
            'max_score' => 10,
            'allow_resubmit' => false,
            'status' => 'published',
        ]);

        \App\Models\LearningMaterial::create([
            'title' => 'New learning material',
            'description' => 'Student handout',
            'school_class_id' => $class->id,
            'subject_id' => $class->subject_id,
            'uploaded_by' => $teacher->id,
            'file_path' => 'materials/sample.pdf',
            'file_type' => 'application/pdf',
        ]);

        $response = $this->withToken($token)->getJson('/api/v1/sync')->assertOk();

        $this->assertContains($quiz->id, collect($response->json('data.quizzes'))->pluck('id')->all());
        $this->assertContains($assignment->id, collect($response->json('data.assignments'))->pluck('id')->all());
        $this->assertContains('New learning material', collect($response->json('data.materials'))->pluck('title')->all());

        $quiz->update(['title' => 'Updated student quiz']);
        $assignment->update(['title' => 'Updated student assignment']);

        $since = $response->json('data.synced_at');
        $updated = $this->withToken($token)->getJson('/api/v1/sync?since='.urlencode($since))->assertOk();

        $this->assertSame('Updated student quiz', collect($updated->json('data.quizzes'))->firstWhere('id', $quiz->id)['title']);
        $this->assertSame('Updated student assignment', collect($updated->json('data.assignments'))->firstWhere('id', $assignment->id)['title']);
    }
}
