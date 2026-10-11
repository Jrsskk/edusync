<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\User;
use App\Notifications\StudentEmailVerificationNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\URL;
use Tests\TestCase;

class StudentMobileRegistrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_mobile_registration_creates_student_and_sends_verification_link(): void
    {
        Notification::fake();

        $this->postJson('/api/v1/register', [
            'name' => 'Avery Marie Student',
            'email' => 'AVERY@example.com',
            'password' => 'StrongPass1!',
            'password_confirmation' => 'StrongPass1!',
        ])->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.email', 'avery@example.com');

        $user = User::where('email', 'avery@example.com')->firstOrFail();
        $this->assertSame(UserRole::Student, $user->role);
        $this->assertNull($user->email_verified_at);
        Notification::assertSentTo($user, StudentEmailVerificationNotification::class);
    }

    public function test_signed_mobile_verification_link_verifies_only_the_matching_student(): void
    {
        $student = User::factory()->create([
            'role' => UserRole::Student,
            'email' => 'student@example.com',
            'email_verified_at' => null,
        ]);
        $url = URL::temporarySignedRoute(
            'api.v1.email.verify',
            now()->addMinutes(10),
            ['id' => $student->id, 'hash' => sha1($student->email)],
        );

        $this->getJson($url)->assertOk()->assertJsonPath('success', true);
        $this->assertNotNull($student->fresh()->email_verified_at);
    }

    public function test_mobile_verification_rejects_an_invalid_signature(): void
    {
        $student = User::factory()->create([
            'role' => UserRole::Student,
            'email_verified_at' => null,
        ]);

        $this->getJson("/api/v1/email/verify/{$student->id}/".sha1($student->email))
            ->assertForbidden();
        $this->assertNull($student->fresh()->email_verified_at);
    }
}
